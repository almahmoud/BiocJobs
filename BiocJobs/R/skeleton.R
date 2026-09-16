## Scaffolding for new job declarations.

#' Scaffold a job declaration in a package
#'
#' Creates `inst/biocjobs/<name>.yaml` and
#' `inst/biocjobs/scripts/<name>.R` in a package source tree, pre-filled
#' with a commented template that
#' demonstrates every specification field and the `jobParams()` script
#' contract.  Nothing is overwritten unless `overwrite = TRUE`.
#'
#' @param name Job name (`[a-z0-9][a-z0-9._-]*`).
#' @param pkg Path to the package source directory (must contain
#'   `DESCRIPTION`).
#' @param title One-line human-readable title; defaults to the job name.
#' @param overwrite Replace existing files (default `FALSE`).
#' @return Invisibly, a character vector with the paths of the two created
#'   files.
#' @examples
#' ## Stand in for a package source tree (normally this is your own
#' ## package's checkout, and you would call jobSkeleton() from its root).
#' pkg <- tempfile("mypackage_")
#' dir.create(file.path(pkg, "R"), recursive = TRUE, showWarnings = FALSE)
#' writeLines(c("Package: mypackage", "Version: 0.99.0"),
#'            file.path(pkg, "DESCRIPTION"))
#'
#' created <- jobSkeleton("my-analysis", pkg = pkg, title = "My analysis")
#' basename(created)
#'
#' ## The scaffold is a valid declaration from the start, so you can
#' ## validate as you edit it down to the real interface.
#' job <- readJob(file.path(pkg, "inst", "biocjobs", "my-analysis.yaml"))
#' job
#' vapply(validateJob(job), `[[`, "", "severity")
#' @export
jobSkeleton <- function(name, pkg = ".", title = NULL, overwrite = FALSE) {
    if (!grepl("^[a-z0-9][a-z0-9._-]*$", name))
        stop("'name' must match ^[a-z0-9][a-z0-9._-]*$")
    desc <- file.path(pkg, "DESCRIPTION")
    if (!file.exists(desc))
        stop("'", pkg, "' is not a package source directory (no DESCRIPTION)")
    package <- unname(read.dcf(desc)[1L, "Package"])
    title <- title %||% name

    dir <- file.path(pkg, "inst", "biocjobs")
    dir.create(file.path(dir, "scripts"), recursive = TRUE,
               showWarnings = FALSE)
    yaml_path <- file.path(dir, paste0(name, ".yaml"))
    script_path <- file.path(dir, "scripts", paste0(name, ".R"))
    for (path in c(yaml_path, script_path))
        if (file.exists(path) && !overwrite)
            stop("'", path, "' already exists (use overwrite = TRUE)")

    writeLines(sprintf(.SKELETON_YAML, name, package, title, name), yaml_path)
    writeLines(sprintf(.SKELETON_SCRIPT, name, name, package, name),
               script_path)
    tidy <- function(x) sub("^\\./", "", x)
    message("created ", tidy(yaml_path), "\ncreated ", tidy(script_path),
            "\nnext: edit both files, then validate with\n  ",
            "Rscript -e 'BiocJobs::biocjobsCLI()' validate ", pkg)
    invisible(c(yaml_path, script_path))
}

.SKELETON_YAML <- 'biocjobs: "1.0"
name: %s
package: %s
title: %s
tagline: one line shown in tool listings
description: >
  Longer description of what this job computes, shown to users of the
  generated wrappers. Two to four sentences.
version: "0.1.0"
license: MIT
script: scripts/%s.R
# depends: [pkgA, pkgB]   # R packages the script needs beyond the host package

inputs:
  - name: input1              # becomes --input1 <path>
    format: tsv               # see BiocJobs::jobFormats()
    label: Short UI label
    help: >
      Longer help text: expected columns, units, how to produce it.

outputs:
  - name: output1             # becomes --output1 <path>
    format: tsv
    label: Short UI label

options:
  - name: method              # becomes --method <value>
    type: choice              # boolean | choice | string | integer | float
    choices: [fast, exact]
    default: fast
    label: Method
  - name: threshold
    type: float
    default: 0.05
    min: 0
    max: 1
    label: Threshold
# string options used as R formulas may need extra Galaxy sanitizer chars:
#  - name: design
#    type: string
#    default: "~ condition"
#    allow_chars: ["~"]

resources:
  cpus: 1
  memory_gb: 4
  disk_gb: 10

# citations:
#   - doi: 10.1000/your.method.paper

# tests:                      # exercised by the generated Galaxy wrapper
#   - inputs:  {input1: test-data/input1.tsv}
#     options: {method: fast}
#     outputs:
#       output1: {file: test-data/output1.tsv, compare: sim_size, delta: 3000}
'

.SKELETON_SCRIPT <- '## BiocJobs job script: %s
## The declared interface lives in ../%s.yaml; jobParams() parses the
## command line against it, so every value below is typed, validated and
## defaulted by the time it returns.

params <- BiocJobs::jobParams("%s", "%s")

## -- your analysis ---------------------------------------------------------
## Read inputs from params$<input name>, honour params$<option name>, and
## write every declared output to params$<output name>. Fail loudly with
## stop() on bad input; never prompt or open devices interactively.

data <- read.delim(params$input1)

result <- data  # ... real work here ...

write.table(result, params$output1, sep = "\\t", quote = FALSE,
            row.names = FALSE)
'
