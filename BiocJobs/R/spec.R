## Job specification: reading and validation.
##
## A job specification is a YAML file shipped at inst/biocjobs/<name>.yaml
## in the host package, next to an R script (conventionally under
## inst/biocjobs/scripts/).
## BiocJobs never evaluates host package code to discover jobs: the YAML is
## the single machine-readable source of truth, so build infrastructure can
## enumerate jobs from a package tarball without installing or loading it.

.SPEC_VERSION <- "1.0"

.OPTION_TYPES <- c("boolean", "choice", "string", "integer", "float")

#' Read a single job specification
#'
#' @param path Path to a job YAML file.
#' @param validate Validate the specification after reading (default `TRUE`).
#' @return A `BiocJob` object (a validated list).
#' @examples
#' ## BiocJobs ships a miniature example package; its declaration is a
#' ## normal inst/biocjobs/<job>.yaml file.
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' yaml <- file.path(toy, "inst", "biocjobs", "toy-normalize.yaml")
#'
#' job <- readJob(yaml)
#' job
#'
#' ## The specification is a plain list: everything generators and the
#' ## runtime contract need is reachable by name.
#' job$version
#' vapply(job$options, `[[`, "", "name")
#' job$options[[1]]$choices
#' @export
readJob <- function(path, validate = TRUE) {
    if (!file.exists(path))
        stop("job specification not found: ", path)
    spec <- yaml::read_yaml(path)
    if (!is.list(spec))
        stop("job specification is not a YAML mapping: ", path)
    spec[["_path"]] <- normalizePath(path)
    ## Normalize scalar fields: YAML may parse them as numbers (name: 123).
    for (field in c("name", "package", "title", "tagline", "description",
                    "version", "script", "license", "container"))
        if (!is.null(spec[[field]]))
            spec[[field]] <- as.character(spec[[field]])[1L]
    ## title and tagline are single-line everywhere they are used (Galaxy
    ## tool name, CLI title, WDL/NF headers); a folded/literal YAML scalar
    ## can carry newlines, so collapse them.
    for (field in c("title", "tagline"))
        if (!is.null(spec[[field]]))
            spec[[field]] <- trimws(gsub("[[:space:]]+", " ", spec[[field]]))
    ## Normalize sections so downstream code can rely on lists of mappings.
    for (section in c("inputs", "outputs", "options", "citations", "tests"))
        if (is.null(spec[[section]]))
            spec[[section]] <- list()
    if (is.null(spec$resources))
        spec$resources <- list()
    if (!is.null(spec$depends))
        spec$depends <- as.character(spec$depends)
    class(spec) <- "BiocJob"
    if (validate) {
        issues <- validateJob(spec)
        errors <- issues[vapply(issues, `[[`, "", "severity") == "error"]
        if (length(errors)) {
            detail <- vapply(errors, `[[`, "", "message")
            stop("invalid job specification '", path, "':\n",
                 paste0("  - ", detail, collapse = "\n"))
        }
    }
    spec
}

#' Discover job specifications in a package
#'
#' Looks for `inst/biocjobs/*.yaml` in a package source directory, or
#' `biocjobs/*.yaml` in an installed package.
#'
#' @param pkg Path to a package source directory, path to an installed package
#'   directory, or the name of an installed package.
#' @param validate Validate each specification (default `TRUE`).
#' @return A named list of `BiocJob` objects.
#' @examples
#' ## Discovery reads YAML only: no host package code is loaded or run, so
#' ## this works on an uninstalled source tree or an unpacked tarball.
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' jobs <- findJobs(toy)
#' names(jobs)
#'
#' jobs[["toy-normalize"]]
#'
#' ## Packages that declare no jobs simply return an empty list.
#' length(findJobs(tempdir()))
#' @export
findJobs <- function(pkg = ".", validate = TRUE) {
    dir <- .jobsDir(pkg)
    if (is.null(dir))
        return(structure(list(), names = character()))
    paths <- sort(list.files(dir, pattern = "\\.ya?ml$", full.names = TRUE))
    jobs <- lapply(paths, readJob, validate = validate)
    names(jobs) <- vapply(jobs, function(j) as.character(j$name %||% ""), "")
    jobs
}

## Resolve the jobs directory for source, installed-by-path, and
## installed-by-name package references.  Returns NULL when absent.
.jobsDir <- function(pkg) {
    if (dir.exists(pkg)) {
        src <- file.path(pkg, "inst", "biocjobs")
        if (dir.exists(src))
            return(src)
        installed <- file.path(pkg, "biocjobs")
        if (dir.exists(installed) && file.exists(file.path(pkg, "DESCRIPTION")))
            return(installed)
        return(NULL)
    }
    found <- system.file("biocjobs", package = pkg)
    if (nzchar(found)) found else NULL
}

## The package root corresponding to a jobs dir reference (for reading
## DESCRIPTION and locating scripts).
.pkgRoot <- function(pkg) {
    if (dir.exists(pkg)) {
        return(normalizePath(pkg))
    }
    root <- system.file(package = pkg)
    if (!nzchar(root))
        stop("package not found: ", pkg)
    root
}

#' Resolve the script path of a job
#'
#' @param job A `BiocJob` object.
#' @return Absolute path to the job's R script.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' script <- jobScript(job)
#' basename(script)
#'
#' ## The script is plain R: one jobParams() call, then analysis code.
#' cat(head(readLines(script), 6), sep = "\n")
#' @export
jobScript <- function(job) {
    stopifnot(inherits(job, "BiocJob"))
    script <- file.path(dirname(job[["_path"]]), job$script)
    if (!file.exists(script))
        stop("job script not found: ", script)
    normalizePath(script)
}

.issue <- function(severity, message) {
    list(severity = severity, message = message)
}

## Issue collector.  validateJob() runs many independent checks and each may
## contribute zero or more issues, so the accumulator has to outlive the
## expression that appends to it.  A small environment carries it explicitly.
.newIssues <- function() {
    collector <- new.env(parent = emptyenv())
    assign("issues", list(), envir = collector)
    collector
}

.addIssue <- function(collector, severity, ...) {
    assign("issues",
           c(get("issues", envir = collector),
             list(.issue(severity, paste0(...)))),
           envir = collector)
    invisible(NULL)
}

.collectedIssues <- function(collector) get("issues", envir = collector)

#' Validate a job specification
#'
#' Checks a specification for structural problems.  Errors make the job
#' unusable; notes are advisory (for example an unrecognized file format,
#' which is passed through verbatim to generators).
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @return A list of issues, each a list with elements `severity` (`"error"`
#'   or `"note"`) and `message`.  Empty when the specification is valid.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' yaml <- file.path(toy, "inst", "biocjobs", "toy-normalize.yaml")
#'
#' ## A clean specification reports nothing.
#' validateJob(yaml)
#'
#' ## Introduce two problems a maintainer might actually make: an option
#' ## whose flag collides with an input, and a default outside its choices.
#' job <- readJob(yaml)
#' job$options[[1]]$name <- "matrix"
#' job$options[[1]]$default <- "sqrt"
#' issues <- validateJob(job)
#' for (i in issues)
#'     cat(i$severity, ": ", i$message, "\n", sep = "")
#'
#' ## Errors make a job unusable; notes are advisory.
#' table(vapply(issues, `[[`, "", "severity"))
#' @export
validateJob <- function(job) {
    if (is.character(job))
        job <- readJob(job, validate = FALSE)
    stopifnot(inherits(job, "BiocJob"))
    collector <- .newIssues()
    add <- function(severity, ...) .addIssue(collector, severity, ...)

    ## ---- top level ----
    if (is.null(job$biocjobs))
        add("error", "missing 'biocjobs' spec version field")
    else if (!identical(as.character(job$biocjobs), .SPEC_VERSION))
        add("note", "spec version '", job$biocjobs, "' differs from ",
            "supported version '", .SPEC_VERSION, "'")
    for (field in c("name", "package", "script", "title")) {
        if (is.null(job[[field]]) || !nzchar(as.character(job[[field]])[1L]))
            add("error", "missing required field '", field, "'")
    }
    if (!is.null(job$name) &&
        !grepl("^[a-z0-9][a-z0-9._-]*$", as.character(job$name)))
        add("error", "'name' must match ^[a-z0-9][a-z0-9._-]*$ (got '",
            job$name, "')")
    ## CLI middle layer: a BiocExecute/Rapp subcommand is the job name with
    ## '-' mapped to '_', which must then be a syntactically valid R name.
    if (!is.null(job$name)) {
        branch <- gsub("-", "_", as.character(job$name), fixed = TRUE)
        if (nzchar(branch) && !identical(make.names(branch), branch))
            add("note", "'name' cannot be exposed as a CLI subcommand by ",
                "BiocExecute/Rapp (\"", branch, "\" is not a valid R name)")
    }
    if (is.null(job$description))
        add("note", "no 'description'; generators will fall back to 'title'")
    if (is.null(job$version))
        add("note", "no 'version'; generators will use '0.1.0'")
    if (!is.null(job[["_path"]]) && !is.null(job$script)) {
        script <- file.path(dirname(job[["_path"]]), job$script)
        if (!file.exists(script))
            add("error", "script not found: ", script)
    }

    ## Entries must be YAML mappings; a bare scalar (e.g. "- counts") would
    ## otherwise crash every downstream accessor.  Filter once per section,
    ## reporting the malformed entries.
    sections <- list()
    for (section in c("inputs", "outputs", "options")) {
        entries <- job[[section]]
        if (!is.list(entries))
            entries <- as.list(entries)
        ok <- vapply(entries, function(e)
            is.list(e) && !is.null(names(e)), NA)
        for (bad in entries[!ok])
            add("error", section, ": entry '",
                paste(utils::head(as.character(bad), 1L), collapse = ""),
                "' is not a mapping (each entry needs name:, type:, ... keys)")
        sections[[section]] <- entries[ok]
    }

    ## ---- inputs / outputs ----
    for (section in c("inputs", "outputs")) {
        entries <- sections[[section]]
        if (identical(section, "inputs") && !length(entries))
            add("note", "job declares no inputs")
        if (identical(section, "outputs") && !length(entries))
            add("error", "job declares no outputs")
        for (e in entries) {
            what <- paste0(substr(section, 1L, nchar(section) - 1L), " '",
                           e$name %||% "?", "'")
            if (is.null(e$name) || !grepl("^[a-z][a-z0-9_]*$", e$name))
                add("error", section, ": each entry needs a 'name' matching ",
                    "^[a-z][a-z0-9_]*$ (got '", e$name %||% "", "')")
            if (is.null(e$format))
                add("error", what, ": missing 'format'")
            else if (!.formatInfo(e$format)$known)
                add("note", what, ": format '", e$format,
                    "' is not in jobFormats(); it is passed through verbatim")
            if (is.null(e$label))
                add("note", what, ": no 'label'")
        }
    }

    ## ---- options ----
    for (o in sections$options) {
        what <- paste0("option '", o$name %||% "?", "'")
        if (is.null(o$name) || !grepl("^[a-z][a-z0-9_]*$", o$name))
            add("error", "options: each entry needs a 'name' matching ",
                "^[a-z][a-z0-9_]*$ (got '", o$name %||% "", "')")
        if (is.null(o$type) || !o$type %in% .OPTION_TYPES)
            add("error", what, ": 'type' must be one of ",
                paste(.OPTION_TYPES, collapse = ", "))
        if (identical(o$type, "choice")) {
            if (length(o$choices) < 2L)
                add("error", what, ": choice options need >= 2 'choices'")
            else if (!is.null(o$default) &&
                     !as.character(o$default) %in% as.character(o$choices))
                add("error", what, ": default '", o$default,
                    "' is not among the declared choices")
        }
        if (!is.null(o$default) && !is.null(o$type) &&
            o$type %in% c("integer", "float", "boolean")) {
            coerced <- tryCatch(.coerceValue(o$default, o), error = identity)
            if (inherits(coerced, "error"))
                add("error", what, ": default '", o$default,
                    "' is not a valid ", o$type)
        }
        if (is.null(o$default) && !isTRUE(o$required))
            add("error", what, ": needs either a 'default' or 'required: true'")
        if (is.null(o$label))
            add("note", what, ": no 'label'")
    }

    ## ---- shared flag namespace ----
    entry_names <- function(section)
        vapply(sections[[section]],
               function(e) as.character(e$name %||% ""), "")
    all_names <- c(entry_names("inputs"), entry_names("outputs"),
                   entry_names("options"))
    dups <- unique(all_names[duplicated(all_names) & nzchar(all_names)])
    if (length(dups))
        add("error", "duplicate parameter names across inputs/outputs/",
            "options: ", paste(dups, collapse = ", "))

    ## ---- resources ----
    for (field in c("cpus", "memory_gb", "disk_gb")) {
        v <- job$resources[[field]]
        if (!is.null(v) && (!is.numeric(v) || length(v) != 1L || v <= 0))
            add("error", "resources: '", field, "' must be a positive number")
    }

    ## ---- citations ----
    for (ci in job$citations) {
        if (!is.list(ci) || (is.null(ci$doi) && is.null(ci$bibtex)))
            add("error", "citations: each entry needs 'doi' or 'bibtex'")
    }

    ## ---- depends ----
    if (!is.null(job$depends)) {
        bad <- !grepl("^[A-Za-z][A-Za-z0-9.]*$", as.character(job$depends))
        if (any(bad))
            add("error", "depends: invalid R package name(s): ",
                paste(as.character(job$depends)[bad], collapse = ", "))
    }

    ## ---- tests ----
    root <- .specPkgRoot(job)
    for (i in seq_along(job$tests)) {
        tc <- job$tests[[i]]
        if (!is.list(tc)) {
            add("error", "tests: entry ", i, " is not a mapping")
            next
        }
        files <- c(unlist(tc$inputs),
                   unlist(lapply(tc$outputs, function(o)
                       if (is.list(o)) o$file else NULL)))
        for (f in as.character(files)) {
            if (!is.null(root) && !file.exists(file.path(root, f)))
                add("note", "tests: file '", f, "' not found relative to ",
                    "the package root; Galaxy test staging will skip it")
        }
    }

    .collectedIssues(collector)
}

#' @export
print.BiocJob <- function(x, ...) {
    cat("BiocJob '", x$name, "' (package ", x$package, ")\n", sep = "")
    cat("  ", x$title, "\n", sep = "")
    fmt <- function(e) paste0(e$name, " <", e$format, ">")
    if (length(x$inputs))
        cat("  inputs:  ",
            paste(vapply(x$inputs, fmt, ""), collapse = ", "), "\n")
    if (length(x$outputs))
        cat("  outputs: ",
            paste(vapply(x$outputs, fmt, ""), collapse = ", "), "\n")
    if (length(x$options))
        cat("  options: ",
            paste(vapply(x$options, function(o) paste0(o$name, " <", o$type,
                                                       ">"), ""),
                  collapse = ", "), "\n")
    invisible(x)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
