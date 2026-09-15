## Command-line interface for automation.
##
## Everything the framework does is reachable from a shell, so build
## infrastructure needs nothing but:
##
##     Rscript -e 'BiocJobs::biocjobsCLI()' <command> <pkg> [job] [options]

.CLI_USAGE <- "
BiocJobs command line interface

usage:
  Rscript -e 'BiocJobs::biocjobsCLI()' <command> [arguments]

commands:
  list     <pkg>                       list jobs declared by a package
  validate <pkg>                       validate all job specs (exit 1 on error)
  manifest <pkg> [--out FILE]          write the package job manifest (JSON)
  tes      <pkg> <job> [--out FILE]    generate a TES task template (JSON)
  galaxy   <pkg> <job> [--out FILE]    generate a Galaxy tool wrapper (XML)
  nextflow <pkg> <job> [--out FILE]    generate a Nextflow DSL2 module
  wdl      <pkg> <job> [--out FILE]    generate a WDL task
  htcondor <pkg> <job> [--out FILE]    generate an HTCondor submit file
  run      <pkg> <job> [--workdir DIR] [--<param> <value> ...]
                                       run a job locally

<pkg> is a package source directory, an installed package directory, or an
installed package name.
"

#' BiocJobs command line interface
#'
#' Entry point for shell-driven use; see the package README for the command
#' reference.  Exits the R session with a non-zero status on failure when
#' run non-interactively.
#'
#' @param args Command-line arguments; defaults to
#'   `commandArgs(trailingOnly = TRUE)`.
#' @return Exits the process when non-interactive; otherwise returns
#'   invisibly.
#' @examples
#' ## The CLI exists for shells and build infrastructure; from R, call the
#' ## same functions it dispatches to.
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#'
#' jobs <- findJobs(toy)                 # biocjobsCLI(c("list", toy))
#' names(jobs)
#'
#' issues <- validateJob(jobs[[1]])      # biocjobsCLI(c("validate", toy))
#' length(issues)                        # 0 => the CLI would exit 0
#'
#' ## biocjobsCLI(c("nextflow", toy, "toy-normalize", "--out", out))
#' out <- file.path(tempdir(), "toy_normalize.nf")
#' nextflowModule(jobs[[1]], file = out)
#' file.exists(out)
#'
#' \dontrun{
#' ## From a shell.  Called non-interactively, biocjobsCLI() quits the
#' ## session with the command's exit status, so it is the whole program:
#' ##   Rscript -e 'BiocJobs::biocjobsCLI()' validate /path/to/pkg
#' biocjobsCLI(c("validate", toy))
#' }
#' @export
biocjobsCLI <- function(args = commandArgs(trailingOnly = TRUE)) {
    status <- tryCatch(.cliDispatch(args), error = function(e) {
        message("error: ", conditionMessage(e))
        1L
    })
    if (!interactive())
        quit(status = status, save = "no")
    invisible(status)
}

.cliDispatch <- function(args) {
    if (!length(args)) {
        message(.CLI_USAGE)
        return(1L)
    }
    command <- args[[1L]]
    rest <- args[-1L]

    if (command %in% c("help", "--help", "-h")) {
        message(.CLI_USAGE)
        return(0L)
    }
    if (!command %in% c("list", "validate", "manifest", "tes", "galaxy",
                        "nextflow", "wdl", "htcondor", "run"))
        stop("unknown command '", command, "'")
    if (!length(rest))
        stop("command '", command, "' needs a package argument")

    pkg <- rest[[1L]]
    rest <- rest[-1L]

    switch(
        command,
        list = {
            jobs <- findJobs(pkg)
            if (!length(jobs)) {
                message("no jobs declared")
            } else {
                for (job in jobs) print(job)
            }
            0L
        },
        validate = {
            jobs <- findJobs(pkg, validate = FALSE)
            if (!length(jobs))
                message("no jobs declared")
            n_err <- 0L
            for (job in jobs) {
                issues <- validateJob(job)
                for (i in issues) {
                    message(job$name %||% "?", ": ", i$severity, ": ",
                            i$message)
                    if (identical(i$severity, "error"))
                        n_err <- n_err + 1L
                }
            }
            if (n_err) {
                message(n_err, " error(s)")
                1L
            } else {
                message("all job specifications valid")
                0L
            }
        },
        manifest = {
            opts <- .parseArgv(rest)
            out <- opts$out
            manifest <- jobManifest(pkg, file = out)
            if (is.null(out))
                cat(jsonlite::toJSON(unclass(manifest), auto_unbox = TRUE,
                                     pretty = TRUE), "\n")
            else message("wrote ", out)
            0L
        },
        tes = ,
        galaxy = ,
        nextflow = ,
        wdl = ,
        htcondor = {
            if (!length(rest))
                stop("command '", command, "' needs a job name")
            jobname <- rest[[1L]]
            opts <- .parseArgv(rest[-1L])
            job <- .cliFindJob(pkg, jobname)
            if (identical(command, "tes")) {
                task <- tesTask(job)
                json <- writeTesTask(task, file = opts$out)
                if (is.null(opts$out)) cat(json, "\n")
                else message("wrote ", opts$out)
            } else if (identical(command, "galaxy")) {
                doc <- galaxyTool(job)
                out <- opts$out %||% paste0(.galaxyToolId(job), ".xml")
                writeGalaxyTool(doc, out, job = job)
                message("wrote ", out)
            } else if (identical(command, "htcondor")) {
                ## Writes the submit file and, beside it, the executable
                ## script the submit file names.
                out <- opts$out %||% paste0(job$name, ".sub")
                htcondorSubmit(job, file = out)
                message("wrote ", out, " and ",
                        file.path(dirname(out), paste0(job$name, ".sh")))
            } else {
                generate <- if (identical(command, "nextflow"))
                    nextflowModule else wdlTask
                text <- generate(job, file = opts$out)
                if (is.null(opts$out)) cat(text, "\n")
                else message("wrote ", opts$out)
            }
            0L
        },
        run = {
            if (!length(rest))
                stop("command 'run' needs a job name")
            jobname <- rest[[1L]]
            opts <- .parseArgv(rest[-1L])
            job <- .cliFindJob(pkg, jobname)
            workdir <- opts$workdir %||% tempfile("biocjob_")
            opts$workdir <- NULL
            result <- runJob(job, params = opts, workdir = workdir)
            message("workdir: ", result$workdir)
            for (name in names(result$outputs))
                message("output ", name, ": ", result$outputs[[name]])
            if (identical(result$status, 0L)) 0L else 1L
        }
    )
}

.cliFindJob <- function(pkg, jobname) {
    jobs <- findJobs(pkg)
    job <- jobs[[jobname]]
    if (is.null(job))
        stop("job '", jobname, "' not found in ", pkg,
             if (length(jobs)) paste0("; available: ",
                                      paste(names(jobs), collapse = ", "))
             else "; the package declares no jobs")
    job
}
