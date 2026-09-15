## HTCondor target.
##
## A job maps onto an HTCondor submit description file plus the executable
## shell script it runs.  HTCondor transfers declared inputs into the job's
## scratch directory, runs one command, and transfers declared outputs back,
## which is the same shape as a GA4GH TES task; resources map to the
## request_* knobs and the job's container to the container universe.
##
## Two files are emitted rather than one because HTCondor's `arguments`
## quoting is its own dialect (embedded double quotes doubled, single quotes
## used for grouping).  Putting the command in a shell script keeps the
## escaping in ordinary bash, and matches the layout the submitr package
## expects: an executable script named by `executable` in the submit file.

## Escape a value for a bash single-quoted string.
.shSquote <- function(value) {
    v <- gsub("'", "'\\''", as.character(value), fixed = TRUE)
    paste0("'", v, "'")
}

## A bare "repo/image:tag" in container_image is read by HTCondor as a path
## to an image file and transferred as an input, which both mangles the
## reference and tries to ship it. A registry reference needs a transport
## prefix; anything that already carries one, or is a path to an image file,
## is left alone.
.condorImage <- function(image) {
    if (grepl("://", image, fixed = TRUE) ||
        grepl("^[./]", image) ||
        grepl("\\.sif$", image))
        image
    else paste0("docker://", image)
}

## HTCondor request_memory / request_disk accept a bare number plus a unit.
.condorSize <- function(gb) {
    gb <- as.numeric(gb)
    if (gb == round(gb)) sprintf("%dGB", as.integer(gb))
    else sprintf("%sGB", format(gb, scientific = FALSE, trim = TRUE))
}

#' Generate an HTCondor submit file from a job
#'
#' Produces an HTCondor submit description file and the executable shell
#' script it runs.  Declared inputs become `transfer_input_files`, declared
#' outputs become `transfer_output_files`, `resources` become
#' `request_cpus`/`request_memory`/`request_disk`, and the job's container
#' becomes a `container_image` under the container universe.  The script
#' runs the same self-locating `BiocJobs::execJob()` command every other
#' target uses.
#'
#' HTCondor has no typed parameter surface, so unlike the Galaxy tool or the
#' WDL task the result is a concrete submission rather than a reusable typed
#' template.  Option values are written into the script: an option's declared
#' default where it has one, and otherwise a `{{options.<name>}}` placeholder
#' in the same convention [tesTask()] uses.  A placeholder that reaches a
#' running job is rejected by name by [jobParams()], so an unfilled
#' submission fails immediately rather than analysing the wrong thing.
#'
#' Because HTCondor transfers input files into the job's scratch directory by
#' basename, the generated script refers to every file by basename.  Point
#' the `transfer_input_files` line at your own files; their names on the
#' submit side do not have to match.
#'
#' The emitted pair is what the \pkg{submitr} package stages and submits to
#' an HTC submit node, so `submitr::htc_upload()` and `submitr::htc_submit()`
#' can take these files directly.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param image Container image; defaults to the job's `container` field,
#'   then to the current Bioconductor docker image.
#' @param file Optional path for the submit file (conventionally
#'   `<job>.sub`).  The executable script is written beside it, named by the
#'   submit file's `executable` line.
#' @param options Named list of option values; unspecified options fall back
#'   to their declared defaults, then to a `{{options.<name>}}` placeholder.
#' @param queue Number of identical jobs to queue.
#' @return The submit file text as a character scalar, invisibly when `file`
#'   is given.
#' @seealso [tesTask()] for the same job as a GA4GH TES task.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' sub <- htcondorSubmit(job, image = "bioconductor/bioconductor_docker:devel")
#' cat(sub)
#'
#' ## Writing the pair out gives the submit file and its executable script,
#' ## which is what submitr stages to an HTC submit node.
#' dir <- file.path(tempdir(), "condor")
#' dir.create(dir, showWarnings = FALSE)
#' htcondorSubmit(job, file = file.path(dir, "toy-normalize.sub"))
#' list.files(dir)
#' @export
htcondorSubmit <- function(job, image = NULL, file = NULL,
                           options = list(), queue = 1L) {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    image <- image %||% job$container %||% .defaultContainer()
    stem <- as.character(job$name)
    script_name <- paste0(stem, ".sh")
    file_of <- function(e) .defaultFileName(e$name, e$format)

    ## ---- the executable script ----
    flag <- function(name, value)
        sprintf("    --%s %s \\", name, .shSquote(value))
    cmd <- c(
        sprintf("Rscript -e 'BiocJobs::execJob(\"%s\", \"%s\")' \\",
                job$package, job$name),
        vapply(job$inputs, function(e) flag(e$name, file_of(e)), ""),
        vapply(job$options, function(o) {
            v <- options[[o$name]] %||% o$default %||%
                sprintf("{{options.%s}}", o$name)
            if (is.logical(v)) v <- tolower(as.character(v))
            flag(o$name, v)
        }, ""),
        vapply(job$outputs, function(e) flag(e$name, file_of(e)), "")
    )
    cmd[length(cmd)] <- sub(" \\\\$", "", cmd[length(cmd)])

    script <- c(
        "#!/bin/bash",
        sprintf("# Generated by BiocJobs %s for the '%s' job of package %s.",
                .biocjobsVersion(), job$name, job$package),
        "# Run by HTCondor inside the container; do not edit by hand.",
        "set -euo pipefail",
        "",
        cmd,
        ""
    )

    ## ---- the submit description ----
    res <- job$resources
    lines <- c(
        sprintf("# Generated by BiocJobs %s from the '%s' job declared in",
                .biocjobsVersion(), job$name),
        sprintf("# Bioconductor package %s (inst/biocjobs/). Do not edit;",
                job$package),
        sprintf(paste0("# regenerate with: Rscript -e ",
                       "'BiocJobs::biocjobsCLI()' htcondor <pkg> %s"),
                job$name),
        "",
        "universe                = container",
        sprintf("container_image         = %s", .condorImage(image)),
        "",
        sprintf("executable              = %s", script_name),
        "",
        paste0("# Input files land in the job's scratch directory by ",
               "basename. Point these"),
        "# at your own files; their names on the submit side may differ.",
        if (length(job$inputs))
            sprintf("transfer_input_files    = %s",
                    paste(vapply(job$inputs, file_of, ""), collapse = ", ")),
        "should_transfer_files   = YES",
        "when_to_transfer_output = ON_EXIT",
        if (length(job$outputs))
            sprintf("transfer_output_files   = %s",
                    paste(vapply(job$outputs, file_of, ""), collapse = ", ")),
        "",
        if (!is.null(res$cpus))
            sprintf("request_cpus            = %d", as.integer(res$cpus)),
        if (!is.null(res$memory_gb))
            sprintf("request_memory          = %s",
                    .condorSize(res$memory_gb)),
        if (!is.null(res$disk_gb))
            sprintf("request_disk            = %s", .condorSize(res$disk_gb)),
        "",
        sprintf("output                  = %s.$(Cluster).$(Process).out", stem),
        sprintf("error                   = %s.$(Cluster).$(Process).err", stem),
        sprintf("log                     = %s.$(Cluster).$(Process).log", stem),
        "",
        sprintf("queue %d", as.integer(queue)),
        ""
    )
    text <- paste(lines, collapse = "\n")

    if (is.null(file))
        return(text)
    writeLines(lines, file)
    script_path <- file.path(dirname(file), script_name)
    writeLines(script, script_path)
    Sys.chmod(script_path, "0755")
    invisible(text)
}
