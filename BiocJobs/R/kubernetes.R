## Kubernetes target.
##
## A job maps onto a batch/v1 Job with a single pod: one init container per
## input downloads it with curl into an emptyDir volume, and the "job"
## container runs the canonical `Rscript -e 'BiocJobs::execJob(...)'`
## command against fixed paths on that volume.  The command is passed as an
## argv, never through a shell, so values need no quoting.  Unknown values
## are `{{...}}` placeholders, as in the TES target.

## DNS-1123 label: lower-case alphanumerics and "-", alphanumeric at both
## ends, at most `max` characters.
.dnsLabel <- function(x, max = 63L) {
    x <- gsub("[^a-z0-9-]", "-", tolower(x))
    x <- substr(sub("^-+", "", x), 1L, max)
    sub("-+$", "", x)
}

## Label values: at most 63 of [A-Za-z0-9._-], alphanumeric at both ends.
.labelValue <- function(x) {
    x <- gsub("[^A-Za-z0-9._-]", "-", x)
    x <- substr(sub("^[^A-Za-z0-9]+", "", x), 1L, 63L)
    sub("[^A-Za-z0-9]+$", "", x)
}

.quantity <- function(x)
    format(as.numeric(x), scientific = FALSE, trim = TRUE)

.gibibytes <- function(gb)
    paste0(.quantity(gb), "Gi")

## yaml writes logicals as yes/no, which YAML 1.2 parsers read as strings.
.yamlBoolean <- function(x)
    structure(ifelse(x, "true", "false"), class = "verbatim")

.checkNames <- function(values, declared, what) {
    nms <- names(values)
    if (length(values) && (is.null(nms) || !all(nzchar(nms))))
        stop("every ", what, " value must be named")
    known <- vapply(declared, `[[`, "", "name")
    unknown <- setdiff(nms, known)
    if (length(unknown))
        stop("unknown ", what, "(s): ", paste(unknown, collapse = ", "),
             "; declared: ", paste(known, collapse = ", "))
}

## Values for the canonical command: paths under `workdir` for files, and
## supplied values, defaults or placeholders for options.
.containerParams <- function(job, options, workdir) {
    params <- list()
    for (e in job$inputs)
        params[[e$name]] <- file.path(workdir, "inputs",
                                      .defaultFileName(e$name, e$format))
    for (e in job$outputs)
        params[[e$name]] <- file.path(workdir, "outputs",
                                      .defaultFileName(e$name, e$format))
    for (o in job$options)
        params[[o$name]] <- options[[o$name]] %||% o$default %||%
            sprintf("{{options.%s}}", o$name)
    params
}

.kubernetesResources <- function(res) {
    requests <- list(
        cpu = if (!is.null(res$cpus)) .quantity(res$cpus),
        memory = if (!is.null(res$memory_gb)) .gibibytes(res$memory_gb),
        `ephemeral-storage` =
            if (!is.null(res$disk_gb)) .gibibytes(res$disk_gb)
    )
    requests <- requests[lengths(requests) > 0L]
    ## Memory is capped at the declared amount; CPU is not capped, so the
    ## job is never throttled.
    resources <- list(requests = requests,
                      limits = requests[intersect("memory", names(requests))])
    resources[lengths(resources) > 0L]
}

#' Generate a Kubernetes Job from a job
#'
#' Produces a `batch/v1` Job manifest.  An init container per input
#' downloads it with `curl` into a volume shared with the job container,
#' which runs the canonical `BiocJobs::execJob()` command with inputs under
#' `<workdir>/inputs` and outputs under `<workdir>/outputs`.  A required
#' input without a URL, and a required option without a value, is emitted
#' as a `{{...}}` placeholder, as in [tesTask()], and the Job is then
#' annotated `biocjobs.template: "true"`.  An optional input without a URL
#' is left out.
#'
#' The Job runs its pod once (`backoffLimit: 0`, `restartPolicy: Never`),
#' mounts no service account token and drops all Linux capabilities.  The
#' pod does not set `runAsNonRoot`, so namespaces enforcing the
#' `restricted` Pod Security Standard reject it; `baseline` admits it.  It
#' is named through `metadata.generateName`, so submit it with
#' `kubectl create -f`; `kubectl apply` needs a fixed name.  The shared
#' volume `work` is an `emptyDir`, lost when the job ends, unless `claim`
#' names a PersistentVolumeClaim to mount instead.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param inputs Named character vector of `http`, `https` or `ftp` URLs to
#'   download the inputs from.
#' @param options Named list of option values; unspecified options fall back
#'   to their declared defaults.
#' @param image Container image; defaults to the job's `container` field.
#'   One of the two is required.  Besides R, BiocJobs and the host package
#'   the image must provide `curl`.
#' @param workdir Working directory inside the containers, where the shared
#'   volume is mounted.
#' @param claim Name of a PersistentVolumeClaim to mount as the shared
#'   volume, so the outputs outlive the pod.
#' @param file Optional path; when supplied the manifest is written there
#'   with [writeKubernetesJob()].
#' @return A list representing the Job, class `"KubernetesJob"`, invisibly
#'   when `file` is given.
#' @seealso [writeKubernetesJob()]
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#' image <- "ghcr.io/example/toy:1.0"
#'
#' ## Without URLs the Job is a template.
#' template <- kubernetesJob(job, image = image)
#' template$metadata$annotations
#'
#' ## With them the Job has no placeholders.
#' k8s <- kubernetesJob(job,
#'                      inputs = c(matrix = "https://example.org/counts.tsv"),
#'                      options = list(method = "zscore"),
#'                      image = image, claim = "toy-results")
#' pod <- k8s$spec$template$spec
#' unlist(pod$initContainers[[1]]$command)
#' unlist(pod$containers[[1]]$command)
#' str(pod$volumes)
#' @export
kubernetesJob <- function(job, inputs = character(), options = list(),
                          image = NULL, workdir = "/biocjob", claim = NULL,
                          file = NULL) {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    .checkNames(inputs, job$inputs, "input")
    .checkNames(options, job$options, "option")
    bad <- names(inputs)[!grepl("^(https?|ftp)://", inputs)]
    if (length(bad))
        stop("input URLs must use http, https or ftp: ",
             paste(bad, collapse = ", "))
    image <- image %||% job$container
    if (is.null(image))
        stop("no image for the Kubernetes Job; declare 'container:' in the ",
             "job spec or pass 'image' (--image on the command line). It ",
             "must provide curl, BiocJobs and ", job$package)

    if (!is.null(claim) && !(is.character(claim) && length(claim) == 1L &&
                             grepl("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", claim)))
        stop("'claim' must be the name of a PersistentVolumeClaim")

    params <- .containerParams(job, options, workdir)
    keep <- vapply(job$inputs, function(e)
        e$name %in% names(inputs) || !isFALSE(e$required), NA)
    staged <- job$inputs[keep]
    params[vapply(job$inputs[!keep], `[[`, "", "name")] <- NULL
    urls <- vapply(staged, function(e) {
        if (e$name %in% names(inputs)) unname(inputs[[e$name]])
        else sprintf("{{inputs.%s.url}}", e$name)
    }, "")

    mounts <- list(list(name = "work", mountPath = workdir))
    hardened <- list(allowPrivilegeEscalation = FALSE,
                     capabilities = list(drop = list("ALL")))
    stage <- Map(function(e, url) list(
        name = .dnsLabel(paste0("stage-", e$name)),
        image = image,
        command = list("curl", "-fsSL", "--create-dirs",
                       "-o", params[[e$name]], url),
        securityContext = hardened,
        volumeMounts = mounts
    ), staged, urls)
    main <- list(
        name = "job",
        image = image,
        command = as.list(jobCommand(job, params)),
        workingDir = workdir,
        resources = .kubernetesResources(job$resources),
        securityContext = hardened,
        volumeMounts = mounts
    )
    disk <- job$resources$disk_gb
    work <- if (!is.null(claim))
        list(name = "work", persistentVolumeClaim = list(claimName = claim))
    else if (is.null(disk))
        list(name = "work", emptyDir = structure(list(), names = character()))
    else list(name = "work", emptyDir = list(sizeLimit = .gibibytes(disk)))

    pod <- list(
        restartPolicy = "Never",
        automountServiceAccountToken = FALSE,
        securityContext = list(seccompProfile = list(type = "RuntimeDefault")),
        initContainers = unname(stage),
        containers = list(main[lengths(main) > 0L]),
        volumes = list(work)
    )
    labels <- list(
        `app.kubernetes.io/managed-by` = "BiocJobs",
        `biocjobs.package` = .labelValue(job$package),
        `biocjobs.job` = .labelValue(job$name)
    )
    annotations <- list(
        `biocjobs.spec` = as.character(job$biocjobs %||% .SPEC_VERSION))
    if (any(grepl("^\\{\\{.*\\}\\}$", c(urls, unlist(params)))))
        annotations$biocjobs.template <- "true"

    manifest <- list(
        apiVersion = "batch/v1",
        kind = "Job",
        ## The API server appends five characters to generateName, and a
        ## Job name must fit in a 63-character label value.
        metadata = list(generateName = paste0(.dnsLabel(job$name, 57L), "-"),
                        labels = labels,
                        annotations = annotations),
        spec = list(
            backoffLimit = 0L,
            template = list(metadata = list(labels = labels),
                            spec = pod[lengths(pod) > 0L])
        )
    )
    class(manifest) <- c("KubernetesJob", "list")
    if (is.null(file))
        return(manifest)
    writeKubernetesJob(manifest, file)
    invisible(manifest)
}

#' Serialize a Kubernetes Job to YAML
#'
#' @param x A `"KubernetesJob"` object from [kubernetesJob()].
#' @param file Optional path; when supplied the YAML is written there.
#' @return The YAML text, headed by a comment naming the job it was
#'   generated from, invisibly when `file` is given.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#' k8s <- kubernetesJob(job, image = "ghcr.io/example/toy:1.0")
#'
#' cat(writeKubernetesJob(k8s))
#'
#' path <- file.path(tempdir(), "toy-normalize.k8s.yaml")
#' writeKubernetesJob(k8s, file = path)
#' file.exists(path)
#' @export
writeKubernetesJob <- function(x, file = NULL) {
    stopifnot(inherits(x, "KubernetesJob"))
    labels <- x$metadata$labels
    header <- c(
        sprintf("# Generated by BiocJobs %s from the '%s' job declared in",
                .biocjobsVersion(), labels[["biocjobs.job"]]),
        sprintf("# Bioconductor package %s (inst/biocjobs/). Do not edit;",
                labels[["biocjobs.package"]]),
        sprintf(paste0("# regenerate with: Rscript -e ",
                       "'BiocJobs::biocjobsCLI()' kubernetes <pkg> %s"),
                labels[["biocjobs.job"]])
    )
    body <- yaml::as.yaml(unclass(x), indent.mapping.sequence = TRUE,
                          handlers = list(logical = .yamlBoolean))
    text <- paste(c(header, sub("\n$", "", body)), collapse = "\n")
    if (is.null(file))
        return(text)
    writeLines(text, file)
    invisible(text)
}
