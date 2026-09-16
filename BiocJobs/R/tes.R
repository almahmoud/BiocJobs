## GA4GH Task Execution Service (TES) target.
##
## A job maps 1:1 onto a TES Task: declared inputs become tesInput entries
## staged to a fixed container path, declared outputs become tesOutput
## entries collected from fixed container paths, resources map to
## tesResources, and the single executor runs the canonical
## `Rscript -e 'BiocJobs::execJob(...)'` command inside a Bioconductor
## container.  Fields not yet known at generation time (data URLs, unset
## required options) are emitted as `{{...}}` placeholders so the JSON can
## be used as a template by submission systems.

## Fallback Bioconductor release when BiocManager is not available at
## generation time.  Overridable via the `image` argument everywhere.
.BIOC_RELEASE_FALLBACK <- "3.23"

.defaultContainer <- function() {
    release <- if (requireNamespace("BiocManager", quietly = TRUE))
        as.character(BiocManager::version())
    else .BIOC_RELEASE_FALLBACK
    paste0("bioconductor/bioconductor_docker:RELEASE_",
           gsub(".", "_", release, fixed = TRUE))
}

#' Generate a GA4GH TES task from a job
#'
#' Produces a TES v1.1 `tesTask` structure ready to POST to a TES
#' implementation's `/tasks` endpoint (Funnel, TESK, ...).  Any input or
#' output whose URL is not supplied, and any required option without a
#' value, is emitted as a `{{...}}` placeholder, making the result a
#' submission template.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param inputs Named character vector of input URLs (e.g.
#'   `c(counts = "s3://bucket/counts.tsv")`).
#' @param outputs Named character vector of destination URLs for outputs.
#' @param options Named list of option values; unspecified options fall back
#'   to their declared defaults.
#' @param image Container image; defaults to the job's `container` field,
#'   then to the current Bioconductor docker image.
#' @param workdir Working directory inside the container.
#' @param tags Additional tags (named character) merged into the task tags.
#' @param bootstrap Prepend an executor that installs the host package,
#'   BiocJobs, and the job's declared `depends` via `BiocManager` if they
#'   are missing from the image.  Default (`NULL`): enabled exactly when the
#'   image is the generic Bioconductor docker image (which ships no analysis
#'   packages); disabled for purpose-built images named via `container:` or
#'   `image`.
#' @return A list representing the TES task, class `"TesTask"`.
#' @seealso [writeTesTask()]
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' ## With no URLs supplied the task is a submission template: unknown
#' ## values are emitted as {{...}} placeholders and tagged as such, so a
#' ## submission system can refuse to POST it unfilled.
#' template <- tesTask(job)
#' template$inputs[[1]]$url
#' template$tags$biocjobs.template
#'
#' ## Fill in the URLs and the task is ready to submit.
#' task <- tesTask(job,
#'                 inputs = c(matrix = "s3://bucket/counts.tsv"),
#'                 outputs = c(normalized = "s3://bucket/normalized.tsv"),
#'                 options = list(method = "zscore"))
#' names(task)
#' task$resources
#'
#' ## Inputs are staged to fixed container paths and the final executor
#' ## runs the canonical command against them.
#' last <- task$executors[[length(task$executors)]]
#' last$image
#' cat(paste(unlist(last$command), collapse = " "), "\n")
#' @export
tesTask <- function(job, inputs = character(), outputs = character(),
                    options = list(), image = NULL, workdir = "/tmp/biocjob",
                    tags = character(), bootstrap = NULL) {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    bootstrap <- bootstrap %||%
        (is.null(image) && is.null(job$container))
    image <- image %||% job$container %||% .defaultContainer()

    in_dir <- file.path(workdir, "inputs")
    out_dir <- file.path(workdir, "outputs")

    url_or_placeholder <- function(urls, name, what) {
        if (name %in% names(urls))
            unname(urls[[name]])
        else sprintf("{{%s.%s.url}}", what, name)
    }
    tes_inputs <- lapply(job$inputs, function(e) {
        list(
            name = e$name,
            description = e$label %||% e$name,
            url = url_or_placeholder(inputs, e$name, "inputs"),
            path = file.path(in_dir, .defaultFileName(e$name, e$format)),
            type = "FILE"
        )
    })
    tes_outputs <- lapply(job$outputs, function(e) {
        list(
            name = e$name,
            description = e$label %||% e$name,
            url = url_or_placeholder(outputs, e$name, "outputs"),
            path = file.path(out_dir, .defaultFileName(e$name, e$format)),
            type = "FILE"
        )
    })

    ## Parameter values for the canonical command: container-side paths for
    ## files, supplied values / defaults / placeholders for options.
    params <- list()
    for (e in job$inputs)
        params[[e$name]] <- file.path(in_dir,
                                      .defaultFileName(e$name, e$format))
    for (e in job$outputs)
        params[[e$name]] <- file.path(out_dir,
                                      .defaultFileName(e$name, e$format))
    for (o in job$options) {
        v <- options[[o$name]] %||% o$default %||%
            sprintf("{{options.%s}}", o$name)
        params[[o$name]] <- v
    }

    resources <- list()
    if (!is.null(job$resources$cpus))
        resources$cpu_cores <- as.integer(job$resources$cpus)
    if (!is.null(job$resources$memory_gb))
        resources$ram_gb <- as.numeric(job$resources$memory_gb)
    if (!is.null(job$resources$disk_gb))
        resources$disk_gb <- as.numeric(job$resources$disk_gb)

    executors <- list()
    if (isTRUE(bootstrap)) {
        pkgs <- unique(c("BiocJobs", job$package,
                         as.character(job$depends %||% character())))
        install_expr <- sprintf(
            paste0("missing <- setdiff(c(%s), rownames(installed.packages()));",
                   " if (length(missing)) BiocManager::install(missing,",
                   " update = FALSE, ask = FALSE)"),
            paste0('"', pkgs, '"', collapse = ", "))
        executors[[length(executors) + 1L]] <- list(
            image = image,
            command = list("Rscript", "-e", install_expr),
            workdir = workdir
        )
    }
    executors[[length(executors) + 1L]] <- list(
        image = image,
        command = as.list(jobCommand(job, params)),
        workdir = workdir
    )

    task_tags <- c(
        `biocjobs.package` = job$package,
        `biocjobs.job` = job$name,
        `biocjobs.spec` = as.character(job$biocjobs %||% .SPEC_VERSION),
        tags
    )
    ## Mark templates so submission tooling can refuse to POST them as-is.
    values <- c(
        vapply(tes_inputs, `[[`, "", "url"),
        vapply(tes_outputs, `[[`, "", "url"),
        unlist(params)
    )
    if (any(grepl("^\\{\\{.*\\}\\}$", values)))
        task_tags <- c(task_tags, `biocjobs.template` = "true")

    task <- list(
        name = paste0(job$package, "/", job$name),
        description = job$description %||% job$title,
        inputs = tes_inputs,
        outputs = tes_outputs,
        resources = resources,
        executors = executors,
        volumes = list(workdir),
        tags = as.list(task_tags)
    )
    ## Drop empty optional sections rather than emitting empty arrays.
    task <- task[vapply(task, length, 0L) > 0L]
    class(task) <- c("TesTask", "list")
    task
}

#' Serialize a TES task to JSON
#'
#' @param task A `"TesTask"` object from [tesTask()].
#' @param file Optional path; when supplied the JSON is written there.
#' @return The JSON string, invisibly when `file` is given.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#' task <- tesTask(job, inputs = c(matrix = "s3://bucket/counts.tsv"))
#'
#' ## Without `file` the JSON is returned, ready to POST to /tasks.
#' json <- writeTesTask(task)
#' substr(json, 1, 120)
#'
#' ## With `file` it is written for check-in beside the package.
#' path <- file.path(tempdir(), "toy-normalize.tes.json")
#' writeTesTask(task, file = path)
#' cat(head(readLines(path), 12), sep = "\n")
#' @export
writeTesTask <- function(task, file = NULL) {
    stopifnot(inherits(task, "TesTask"))
    json <- jsonlite::toJSON(unclass(task), auto_unbox = TRUE, pretty = TRUE)
    if (is.null(file))
        return(json)
    writeLines(json, file)
    invisible(json)
}
