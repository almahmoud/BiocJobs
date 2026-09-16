## The canonical invocation.
##
## Every execution target (local run, TES task, Galaxy wrapper) launches a
## job with the same self-locating command:
##
##     Rscript -e 'BiocJobs::execJob("<package>", "<job>")' --name value ...
##
## `execJob()` resolves the job script inside the *installed* host package
## and sources it; the script's own `jobParams()` call then parses the
## trailing arguments.  No absolute paths ever appear in generated artifacts.

#' Execute a job from an installed package
#'
#' The canonical entry point used by generated TES tasks and Galaxy wrappers.
#' Locates the job's script inside the installed host package and runs it.
#' Command-line arguments after the `-e` expression are consumed by the
#' script's `jobParams()` call.
#'
#' A CLI layer that has already parsed the command line (such as a
#' BiocExecute/Rapp application generated from the job specification) can
#' hand its parameter values over directly via `values`; the script's
#' `jobParams()` call then uses them instead of re-parsing
#' `commandArgs()`.
#' Values of `NULL`, `NA` or `""` count as "not
#' supplied", so defaults and required-parameter checks behave exactly
#' as on the command line.
#'
#' @param package Name of the installed host package.
#' @param job Job name as declared in the specification.
#' @param values Optional named list of parameter values supplied by a CLI
#'   layer, bypassing command-line parsing.
#' @return Invisibly, the value of the sourced script.
#' @examples
#' ## execJob() normally resolves the script inside the *installed* host
#' ## package.  The toy package ships with BiocJobs but is not installed,
#' ## so point the development override at its specification.
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' yaml <- file.path(toy, "inst", "biocjobs", "toy-normalize.yaml")
#'
#' counts <- file.path(tempdir(), "execjob-counts.tsv")
#' write.table(data.frame(id = c("g1", "g2"), s1 = c(1, 3), s2 = c(5, 7)),
#'             counts, sep = "\t", quote = FALSE, row.names = FALSE)
#' out <- file.path(tempdir(), "execjob-normalized.tsv")
#'
#' previous <- Sys.getenv("BIOCJOBS_SPEC", unset = NA)
#' Sys.setenv(BIOCJOBS_SPEC = yaml)
#'
#' ## `values` is the hand-over a CLI layer (BiocExecute/Rapp) uses once it
#' ## has parsed the command line itself.  The equivalent shell run is
#' ##   Rscript -e 'BiocJobs::execJob("toy", "toy-normalize")'
#' ##       --matrix counts.tsv --normalized norm.tsv --method log2
#' execJob("toy", "toy-normalize",
#'         values = list(matrix = counts, normalized = out,
#'                       method = "log2", center = FALSE))
#' read.delim(out)
#'
#' if (is.na(previous)) Sys.unsetenv("BIOCJOBS_SPEC") else
#'     Sys.setenv(BIOCJOBS_SPEC = previous)
#' @export
execJob <- function(package, job, values = NULL) {
    spec <- .locateSpec(package, job)
    script <- jobScript(spec)
    ## Let jobParams() inside the script resolve the same spec even when the
    ## override mechanism was used to find it.  The hand-over is in-process
    ## (no environment variable to leak into unrelated children) and the
    ## caller's active spec is restored, so nested execJob() calls stack.
    previous_spec <- .activeSpec()
    .setActiveSpec(spec)
    on.exit(.setActiveSpec(previous_spec), add = TRUE)
    if (!is.null(values)) {
        ## Save/restore (not clear-on-exit) so nested execJob() calls stack
        ## correctly; jobParams() consumes the values, so the restore only
        ## matters for an outer frame that had its own pending values.
        previous_values <- .suppliedValues()
        .setSuppliedValues(values)
        on.exit(.setSuppliedValues(previous_values), add = TRUE)
    }
    message("BiocJobs: running ", package, "/", job, " (", script, ")")
    env <- new.env(parent = globalenv())
    invisible(source(script, echo = FALSE, local = env))
}

#' Build the command line for a job
#'
#' Returns the argv vector that launches a job with the given parameter
#' values.  This single builder is used by `runJob()` and by the TES
#' generator, so all execution paths stay in lockstep.
#'
#' Two command styles exist.  `"rscript"` (the default) is self-locating
#' and works in any environment with R and the packages installed; it is
#' what every generated artifact uses.  `"cli"` produces the
#' `<Package> <job> --flag value` form served by a BiocExecute/Rapp
#' launcher; it requires that launcher to be installed on the PATH of the
#' execution environment, so it is intended for interactive use and for
#' registry consumers that know their environment provides it.
#'
#' @param job A `BiocJob` object.
#' @param params Named list or character vector of parameter values
#'   (inputs as paths/placeholders, outputs as paths, options as values).
#' @param rscript Path or name of the `Rscript` executable.
#' @param style `"rscript"` (default) or `"cli"` (BiocExecute/Rapp
#'   launcher form).
#' @return Character vector: the full argv, element one the executable.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' values <- list(matrix = "counts.tsv", normalized = "norm.tsv",
#'                method = "zscore", center = TRUE, pseudocount = 0.5)
#'
#' ## The self-locating form every generated artifact embeds.  Logical
#' ## values render as the "true"/"false" the runtime contract expects.
#' argv <- jobCommand(job, values)
#' cat(paste(argv, collapse = " "), "\n")
#'
#' ## The same run through a BiocExecute/Rapp launcher on the PATH.
#' cat(paste(jobCommand(job, values, style = "cli"), collapse = " "), "\n")
#' @export
jobCommand <- function(job, params = list(), rscript = "Rscript",
                       style = c("rscript", "cli")) {
    stopifnot(inherits(job, "BiocJob"))
    style <- match.arg(style)
    argv <- if (identical(style, "cli")) {
        c(job$package, cliJobName(job))
    } else {
        c(rscript, "-e",
          sprintf('BiocJobs::execJob("%s", "%s")', job$package, job$name))
    }
    for (name in names(params)) {
        value <- params[[name]]
        if (is.null(value))
            next
        if (isTRUE(value))  value <- "true"
        if (isFALSE(value)) value <- "false"
        argv <- c(argv, paste0("--", name), as.character(value))
    }
    argv
}


#' CLI token of a job under a BiocExecute/Rapp launcher
#'
#' A job compiled into a BiocExecute/Rapp application becomes a subcommand
#' whose R branch name replaces `-` with `_` (branch names must be valid
#' R names) and whose command-line token renders `_` back as `-`.  The
#' round-tripped token therefore equals the job name with every underscore
#' shown as a dash.
#'
#' @param job A `BiocJob` object.
#' @return The command-line token, a character scalar.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' cliJobName(job)                       # dashes survive the round trip
#'
#' ## Underscores do not: they become dashes on the command line, because
#' ## the R branch name in between must be a valid R name.
#' job$name <- "toy_normalize.v2"
#' cliJobName(job)
#' @export
cliJobName <- function(job) {
    stopifnot(inherits(job, "BiocJob"))
    gsub("_", "-", as.character(job$name), fixed = TRUE)
}

#' Run a job locally
#'
#' Runs a job in a fresh `Rscript` process, without requiring the host
#' package's jobs to be installed: the specification path is passed to the
#' child process via the `BIOCJOBS_SPEC` environment variable, so a job can
#' be exercised straight from a package source checkout.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param params Named list of parameter values (see `jobCommand()`).
#' @param workdir Working directory for the run (created if needed);
#'   defaults to a fresh temporary directory.  Relative output paths land
#'   here.
#' @param rscript Path or name of the `Rscript` executable.
#' @return Invisibly, a list with `status` (exit code), `workdir`, and
#'   `outputs` (named vector of absolute paths to declared outputs).
#' @examples
#' ## The development loop: edit the script, run it against real data,
#' ## straight from the source checkout -- nothing needs to be installed.
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' counts <- file.path(tempdir(), "runjob-counts.tsv")
#' write.table(data.frame(id = c("g1", "g2", "g3"),
#'                        s1 = c(1, 2, 3), s2 = c(4, 5, 6)),
#'             counts, sep = "\t", quote = FALSE, row.names = FALSE)
#'
#' result <- runJob(job,
#'                  params = list(matrix = counts, method = "none",
#'                                center = TRUE),
#'                  workdir = tempfile("toyrun_"))
#'
#' result$status                     # 0 on success
#' names(result$outputs)             # every declared output, located
#' read.delim(result$outputs[["normalized"]])
#' @export
runJob <- function(job, params = list(), workdir = tempfile("biocjob_"),
                   rscript = "Rscript") {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    if (!dir.exists(workdir))
        dir.create(workdir, recursive = TRUE)

    ## Make relative input paths survive the working-directory change.
    for (e in job$inputs) {
        v <- params[[e$name]]
        if (!is.null(v) && file.exists(v))
            params[[e$name]] <- normalizePath(v)
    }

    ## Run the script directly (not via execJob) so an uninstalled source
    ## checkout works; jobParams() picks the spec up from the environment.
    script <- jobScript(job)
    argv <- character()
    for (name in names(params)) {
        value <- params[[name]]
        if (is.null(value))
            next
        if (isTRUE(value))  value <- "true"
        if (isFALSE(value)) value <- "false"
        argv <- c(argv, paste0("--", name), as.character(value))
    }

    owd <- setwd(workdir)
    on.exit(setwd(owd), add = TRUE)
    status <- system2(rscript, c(shQuote(script), shQuote(argv)),
                      env = paste0("BIOCJOBS_SPEC=",
                                   shQuote(job[["_path"]])))

    outputs <- vapply(job$outputs, function(e) {
        path <- params[[e$name]] %||% .defaultFileName(e$name, e$format)
        if (!file.exists(path)) NA_character_ else normalizePath(path)
    }, "")
    names(outputs) <- vapply(job$outputs, `[[`, "", "name")

    if (!identical(status, 0L))
        warning("job exited with status ", status)
    missing <- names(outputs)[is.na(outputs)]
    if (length(missing))
        warning("declared output(s) not produced: ",
                paste(missing, collapse = ", "))

    invisible(list(status = status, workdir = normalizePath(workdir),
                   outputs = outputs))
}
