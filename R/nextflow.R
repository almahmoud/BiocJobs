## Nextflow target.
##
## A job maps onto a DSL2 process in its own module file: declared file
## inputs become a single nf-core style `tuple val(meta), path(...)` input,
## options become `val` inputs, outputs are emitted under stable names
## carrying `meta` through, and resources map to process directives.  The
## script
## block runs the same self-locating `Rscript -e 'BiocJobs::execJob(...)'`
## command used by every other target, and a stub block makes the module
## testable with `nextflow run -stub` in environments without R.

.nextflowProcessName <- function(job) {
    name <- toupper(gsub("[^A-Za-z0-9_]", "_", as.character(job$name)))
    if (!grepl("^[A-Za-z]", name))    # a leading digit is not a legal name
        name <- paste0("JOB_", name)
    name
}

## Groovy reserved words that would be illegal as a process input variable.
.NF_RESERVED <- c("as", "assert", "break", "case", "catch", "class", "const",
                  "continue", "def", "default", "do", "else", "enum",
                  "extends", "false", "finally", "for", "goto", "if",
                  "implements", "import", "in", "instanceof", "interface",
                  "native", "new", "null", "package", "private", "protected",
                  "public", "return", "static", "strictfp", "super", "switch",
                  "synchronized", "this", "throw", "throws", "trait",
                  "transient", "true", "try", "val", "var", "void", "volatile",
                  "while", "path", "tuple", "env", "stdin", "stdout", "meta")

## A Groovy-safe input variable name; the emitted --flag keeps the original.
.nfVar <- function(name)
    if (name %in% .NF_RESERVED) paste0(name, "_") else name

## Escape a value for a bash single-quoted argument inside a Groovy string:
## '${(value as String).replace("'", "'\\''")}'.
.nfSquote <- function(var) {
    sq <- "'"; dq <- '"'; bs <- "\\"
    ## Groovy collapses \\' in a double-quoted string to ', so the
    ## replacement needs a doubled backslash to survive as one \ at runtime.
    paste0(sq, "${(", var, " as String).replace(",
           dq, sq, dq, ", ", dq, sq, bs, bs, sq, sq, dq, ")}", sq)
}

#' Generate a Nextflow DSL2 module from a job
#'
#' Produces a self-contained Nextflow module file with one process.
#' Options become `val` inputs (pass `params.<name>`-style values or channel
#' values from the calling workflow), and a `stub` block is included so
#' pipelines can be smoke-tested with `-stub-run`.
#'
#' By default the module follows the nf-core convention: the job's file
#' inputs travel together in one `tuple val(meta), path(...)` input led by a
#' `meta` map, every output is emitted as `tuple val(meta), path(...)` so
#' that map flows on to the next process, and the process `tag` is
#' `${meta.id}`.  Nextflow shows the tag of the most recently launched job
#' for a process, so it has to identify the unit of work rather than repeat
#' the process name.  Passing `meta = FALSE` emits plain `path` inputs and
#' tags with the first input file's name instead, for pipelines that do not
#' use meta maps.
#'
#' @param job A `BiocJob` object, or path to a job YAML file.
#' @param image Container image; defaults to the job's `container` field,
#'   then to the current Bioconductor docker image.
#' @param file Optional path; when supplied the module text is written
#'   there.
#' @param meta Emit nf-core style `meta` maps (default `TRUE`).
#' @return The module text as a character scalar, invisibly when `file` is
#'   given.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' job <- readJob(file.path(toy, "inst", "biocjobs", "toy-normalize.yaml"))
#'
#' nf <- nextflowModule(job)
#'
#' ## The process header: resource directives and container come from the
#' ## specification, file inputs become `path`, options become `val`.
#' lines <- strsplit(nf, "\n", fixed = TRUE)[[1]]
#' cat(head(lines, 20), sep = "\n")
#'
#' ## Outputs are emitted under their declared names, so a calling
#' ## workflow refers to them as TOY_NORMALIZE.out.normalized, and carry the
#' ## meta map through to the next process.
#' grep("emit:", lines, value = TRUE)
#'
#' ## The tag identifies the unit of work, not the process.
#' grep("tag ", lines, value = TRUE)
#'
#' ## Pipelines that do not use meta maps can opt out.
#' plain <- strsplit(nextflowModule(job, meta = FALSE), "\n", fixed = TRUE)[[1]]
#' grep("tag |path matrix", plain, value = TRUE)
#'
#' ## Written straight into a pipeline's modules/ directory.
#' path <- file.path(tempdir(), "toy_normalize.nf")
#' nextflowModule(job, file = path)
#' basename(path)
#' @export
nextflowModule <- function(job, image = NULL, file = NULL,
                           meta = TRUE) {
    if (is.character(job))
        job <- readJob(job)
    stopifnot(inherits(job, "BiocJob"))
    image <- image %||% job$container %||% .defaultContainer()
    proc <- .nextflowProcessName(job)
    out_file <- function(e) .defaultFileName(e$name, e$format)

    comment_for <- function(e, kind) {
        note <- if (identical(kind, "option")) {
            extras <- c(
                if (identical(e$type, "choice"))
                    paste0("one of: ", paste(as.character(e$choices),
                                             collapse = ", "))
                else e$type,
                if (!is.null(e$default))
                    paste0("default in spec: ",
                           if (is.logical(e$default))
                               tolower(as.character(e$default))
                           else e$default),
                if (isTRUE(e$required)) "required")
            paste(extras, collapse = "; ")
        } else {
            e$format
        }
        sprintf("// %s (%s)", .oneline(e$label %||% e$name), note)
    }

    ## nf-core convention: the file inputs of one analysis unit travel in a
    ## single tuple led by a `meta` map, outputs carry that map back out, and
    ## the tag names the sample rather than the process.
    if (meta) {
        in_comments <- c(
            "// meta: map identifying the unit of work; meta.id names the tag",
            vapply(job$inputs, function(e)
                sprintf("// %s: %s (%s)", .nfVar(e$name),
                        .oneline(e$label %||% e$name), e$format), ""))
        tuple_parts <- c("val(meta)",
                         vapply(job$inputs, function(e)
                             sprintf("path(%s)", .nfVar(e$name)), ""))
        inputs <- c(in_comments,
                    paste0("tuple ", paste(tuple_parts, collapse = ", ")))
        outputs <- vapply(job$outputs, function(e)
            sprintf("tuple val(meta), path('%s'), emit: %s",
                    out_file(e), e$name), "")
    } else {
        inputs <- unlist(lapply(job$inputs, function(e)
            c(comment_for(e, "input"), sprintf("path %s", .nfVar(e$name)))))
        outputs <- vapply(job$outputs, function(e)
            sprintf("path '%s', emit: %s", out_file(e), e$name), "")
    }
    options <- unlist(lapply(job$options, function(o)
        c(comment_for(o, "option"), sprintf("val %s", .nfVar(o$name)))))

    ## Values are quoted with embedded single quotes escaped, so a path
    ## or option value containing a quote cannot break the shell.
    script <- c(
        sprintf("Rscript -e 'BiocJobs::execJob(\"%s\", \"%s\")' \\\\",
                job$package, job$name),
        vapply(job$inputs, function(e)
            sprintf("    --%s %s \\\\", e$name, .nfSquote(.nfVar(e$name))), ""),
        vapply(job$options, function(o)
            sprintf("    --%s %s \\\\", o$name, .nfSquote(.nfVar(o$name))), ""),
        vapply(job$outputs, function(e)
            sprintf("    --%s '%s' \\\\", e$name, out_file(e)), "")
    )
    script[length(script)] <- sub(" \\\\\\\\$", "", script[length(script)])

    ## The tag identifies the unit of work in Nextflow's progress output, so
    ## it must vary per sample, not per process.
    tag <- if (meta) {
        "${meta.id}"
    } else if (length(job$inputs)) {
        sprintf("${%s.name}", .nfVar(job$inputs[[1L]]$name))
    } else {
        job$name
    }
    directives <- c(
        sprintf("tag \"%s\"", tag),
        sprintf("container '%s'", image),
        if (!is.null(job$resources$cpus))
            sprintf("cpus %d", as.integer(job$resources$cpus)),
        if (!is.null(job$resources$memory_gb))
            sprintf("memory '%s GB'", job$resources$memory_gb),
        if (!is.null(job$resources$disk_gb))
            sprintf("disk '%s GB'", job$resources$disk_gb)
    )

    indent <- function(lines, n)
        if (length(lines)) paste0(strrep(" ", n), lines) else character()

    text <- paste(c(
        sprintf("// Generated by BiocJobs %s from the '%s' job declared in",
                .biocjobsVersion(), job$name),
        sprintf("// Bioconductor package %s (inst/biocjobs/). Do not edit;",
                job$package),
        sprintf(paste0("// regenerate with: Rscript -e ",
                       "'BiocJobs::biocjobsCLI()' nextflow <pkg> %s"),
                job$name),
        "",
        sprintf("process %s {", proc),
        indent(directives, 4),
        "",
        "    input:",
        indent(inputs, 4),
        indent(options, 4),
        "",
        "    output:",
        indent(outputs, 4),
        "",
        "    script:",
        "    \"\"\"",
        indent(script, 4),
        "    \"\"\"",
        "",
        "    stub:",
        "    \"\"\"",
        indent(vapply(job$outputs, function(e)
            sprintf("touch '%s'", out_file(e)), ""), 4),
        "    \"\"\"",
        "}"
    ), collapse = "\n")

    if (is.null(file))
        return(text)
    writeLines(text, file)
    invisible(text)
}
