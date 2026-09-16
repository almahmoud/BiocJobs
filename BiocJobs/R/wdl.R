## WDL target.
##
## A job maps onto a single WDL task (version 1.0 for maximum engine
## compatibility): declared inputs become File inputs, options become typed
## inputs with defaults, outputs are collected from the fixed file names the
## canonical command writes into the task working directory, and resources
## map to the runtime section.  The command is the same self-locating
## `Rscript -e 'BiocJobs::execJob(...)'` used by every other target.

.wdlIdentifier <- function(name) {
    id <- gsub("[^A-Za-z0-9_]", "_", as.character(name))
    if (!grepl("^[A-Za-z]", id))
        id <- paste0("job_", id)
    id
}

.wdlString <- function(x) {
    x <- gsub("\\", "\\\\", .oneline(x), fixed = TRUE)
    x <- gsub('"', '\\"', x, fixed = TRUE)
    ## In a WDL 1.0 double-quoted string, ~{ and ${ open placeholders; a
    ## literal introducer must be escaped. \~ / \$ are 1.1-only, so use
    ## unicode escapes, which parse in 1.0.
    x <- gsub("~{", "\\u007E{", x, fixed = TRUE)
    x <- gsub("${", "\\u0024{", x, fixed = TRUE)
    paste0('"', x, '"')
}

.oneline <- function(x)
    trimws(gsub("[[:space:]]+", " ", paste(as.character(x), collapse = " ")))

## float maps to String so the exact submitted value reaches the command
## (WDL Float stringifies with fixed 6-decimal precision, losing small or
## high-precision values); the R jobParams() layer re-coerces and
## bounds-checks it. Int and Boolean are exact, so they keep their types.
.wdlType <- function(type) {
    switch(type,
           boolean = "Boolean",
           integer = "Int",
           float   = ,
           choice  = ,
           string  = "String",
           stop("unsupported option type: ", type))
}

.wdlLiteral <- function(value, type) {
    switch(type,
           boolean = if (isTRUE(.coerceValue(value, list(type = "boolean"))))
               "true" else "false",
           integer = as.character(as.integer(value)),
           float   = .wdlString(format(as.numeric(value),
                                       scientific = FALSE, trim = TRUE)),
           .wdlString(value))
}

## WDL reserved words that would collide with an input variable name.
.WDL_RESERVED <- c("version", "import", "as", "alias", "task", "workflow",
                   "call", "input", "output", "runtime", "meta",
                   "parameter_meta", "command", "scatter", "if", "then",
                   "else", "struct", "object", "true", "false", "null",
                   "None", "after", "in", "left", "right")

## A WDL-safe variable name: option/input names match ^[a-z][a-z0-9_]*, so
## the only collision risk is a reserved word, resolved by a trailing "_".
## The command still emits the original --flag.
.wdlVar <- function(name)
    if (name %in% .WDL_RESERVED) paste0(name, "_") else name

## Bash single-quote escape as a bare WDL expression: sub(var, "'", "'\\''").
## Turns every embedded single quote into the standard '\'' sequence.
.wdlSubExpr <- function(var) {
    sq <- "'"; dq <- '"'; bs <- "\\"
    ## WDL parses \\' in a double-quoted literal to ', so the replacement
    ## needs a doubled backslash to survive as one \ in the runtime value.
    paste0("sub(", var, ", ", dq, sq, dq, ", ",
           dq, sq, bs, bs, sq, sq, dq, ")")
}

## The same, wrapped as a single-quoted bash argument for a top-level command
## line (a single ~{} placeholder, so usable outside another placeholder).
.wdlSquote <- function(var)
    paste0("'~{", .wdlSubExpr(var), "}'")

## Help line for parameter_meta: label, help, and constraints the WDL type
## system cannot express (choices, bounds, file format).
.wdlHelp <- function(e, kind = c("input", "output", "option")) {
    kind <- match.arg(kind)
    parts <- c(e$label %||% e$name, .oneline(e$help %||% ""))
    if (kind != "option")
        parts <- c(parts, paste0("Format: ", e$format, "."))
    if (identical(e$type, "choice"))
        parts <- c(parts, paste0("One of: ",
                                 paste(as.character(e$choices),
                                       collapse = ", "), "."))
    if (!is.null(e$min) || !is.null(e$max))
        parts <- c(parts, paste0("Range: ", e$min %||% "-Inf", " to ",
                                 e$max %||% "Inf", "."))
    .oneline(paste(parts[nzchar(parts)], collapse = ". "))
}

#' Generate a WDL task from a job
#'
#' Produces a self-contained WDL 1.0 document with one task: File inputs,
#' typed option inputs with defaults, outputs collected from the working
#' directory, a runtime section from the declared resources, and
#' `parameter_meta` carrying the labels, help text and constraints
#' (choices, bounds, formats) that the WDL type system cannot express.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param image Container image; defaults to the job's `container` field,
#'   then to the current Bioconductor docker image.
#' @param file Optional path; when supplied the WDL text is written there.
#' @return The WDL document as a character scalar, invisibly when `file`
#'   is given.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' wdl <- wdlTask(job)
#' lines <- strsplit(wdl, "\n", fixed = TRUE)[[1]]
#'
#' ## Spec defaults become WDL defaults, so the engine itself enforces
#' ## which inputs a submission must provide.
#' cat(head(lines, 23), sep = "\n")
#'
#' ## Constraints the WDL type system cannot express -- choices, bounds,
#' ## formats, help text -- ride along in parameter_meta.
#' grep("One of:|Format:", lines, value = TRUE)
#'
#' path <- file.path(tempdir(), "toy_normalize.wdl")
#' wdlTask(job, file = path)
#' basename(path)
#' @export
wdlTask <- function(job, image = NULL, file = NULL) {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    image <- image %||% job$container %||% .defaultContainer()
    task <- .wdlIdentifier(job$name)

    ## ---- input declarations ---- (variable names are reserved-word safe)
    decls <- character()
    for (e in job$inputs) {
        opt <- if (isFALSE(e$required)) "?" else ""
        decls <- c(decls, sprintf("File%s %s", opt, .wdlVar(e$name)))
    }
    for (o in job$options) {
        type <- .wdlType(o$type)
        decls <- c(decls, if (is.null(o$default))
            sprintf("%s %s", type, .wdlVar(o$name))
        else
            sprintf("%s %s = %s", type, .wdlVar(o$name),
                    .wdlLiteral(o$default, o$type)))
    }

    ## ---- command ----
    out_file <- function(e) .defaultFileName(e$name, e$format)
    ## Int and Boolean render as shell-safe tokens and go unquoted; every
    ## other value is single-quoted with embedded quotes escaped, so a value
    ## containing a quote can neither break the shell nor inject commands.
    opt_flag <- function(o) {
        v <- .wdlVar(o$name)
        if (o$type %in% c("integer", "boolean"))
            sprintf("    --%s ~{%s} \\", o$name, v)
        else
            sprintf("    --%s %s \\", o$name, .wdlSquote(v))
    }
    cmd <- c(
        sprintf("Rscript -e 'BiocJobs::execJob(\"%s\", \"%s\")' \\",
                job$package, job$name),
        vapply(job$inputs, function(e) {
            v <- .wdlVar(e$name)
            if (isFALSE(e$required))
                sprintf(
                    paste0("    ~{if defined(%s) then \"--%s '\" + %s",
                           " + \"'\" else \"\"} \\"),
                    v, e$name, .wdlSubExpr(v))
            else
                sprintf("    --%s %s \\", e$name, .wdlSquote(v))
        }, ""),
        vapply(job$options, opt_flag, ""),
        vapply(job$outputs, function(e)
            sprintf("    --%s '%s' \\", e$name, out_file(e)), "")
    )
    cmd[length(cmd)] <- sub(" \\\\$", "", cmd[length(cmd)])

    ## ---- parameter_meta (inputs only; outputs are not parameters) ----
    pmeta <- c(
        vapply(job$inputs, function(e)
            sprintf("%s: %s", .wdlVar(e$name),
                    .wdlString(.wdlHelp(e, "input"))), ""),
        vapply(job$options, function(o)
            sprintf("%s: %s", .wdlVar(o$name),
                    .wdlString(.wdlHelp(o, "option"))), "")
    )

    outputs <- vapply(job$outputs, function(e)
        sprintf("File %s = \"%s\"", e$name, out_file(e)), "")

    runtime <- c(
        sprintf("docker: %s", .wdlString(image)),
        if (!is.null(job$resources$cpus))
            sprintf("cpu: %d", as.integer(job$resources$cpus)),
        if (!is.null(job$resources$memory_gb))
            sprintf("memory: \"%s GB\"", job$resources$memory_gb),
        if (!is.null(job$resources$disk_gb))
            sprintf("disks: \"local-disk %d HDD\"",
                    as.integer(job$resources$disk_gb))
    )

    indent <- function(lines, n)
        if (length(lines)) paste0(strrep(" ", n), lines) else character()

    text <- paste(c(
        "version 1.0",
        "",
        sprintf("# Generated by BiocJobs %s from the '%s' job declared in",
                .biocjobsVersion(), job$name),
        sprintf("# Bioconductor package %s (inst/biocjobs/). Do not edit;",
                job$package),
        sprintf(paste0("# regenerate with: Rscript -e ",
                       "'BiocJobs::biocjobsCLI()' wdl <pkg> %s"),
                job$name),
        "",
        sprintf("task %s {", task),
        "    input {",
        indent(decls, 8),
        "    }",
        "",
        "    command <<<",
        "        set -euo pipefail",
        indent(cmd, 8),
        "    >>>",
        "",
        "    output {",
        indent(outputs, 8),
        "    }",
        "",
        "    runtime {",
        indent(runtime, 8),
        "    }",
        "",
        "    parameter_meta {",
        indent(pmeta, 8),
        "    }",
        "",
        "    meta {",
        indent(c(sprintf("description: %s",
                         .wdlString(job$description %||% job$title)),
                 sprintf("biocjobs_package: %s", .wdlString(job$package)),
                 sprintf("biocjobs_job: %s", .wdlString(job$name)),
                 sprintf("biocjobs_job_version: %s",
                         .wdlString(job$version %||% "0.1.0"))), 8),
        "    }",
        "}"
    ), collapse = "\n")

    if (is.null(file))
        return(text)
    writeLines(text, file)
    invisible(text)
}
