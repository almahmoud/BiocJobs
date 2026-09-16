## Path helpers for the shipped toy example package.

toy_pkg <- function() {
    path <- system.file("examples", "toy", package = "BiocJobs")
    stopifnot(nzchar(path))
    path
}

toy_yaml <- function() {
    file.path(toy_pkg(), "inst", "biocjobs", "toy-normalize.yaml")
}

toy_job <- function() {
    readJob(toy_yaml())
}

## A small numeric matrix on disk, returned as a path.
toy_matrix_file <- function(dir = tempfile("toydata_")) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    path <- file.path(dir, "matrix.tsv")
    m <- matrix(1:12, nrow = 4,
                dimnames = list(paste0("g", 1:4), paste0("s", 1:3)))
    write.table(data.frame(id = rownames(m), m),
                path, sep = "\t", quote = FALSE, row.names = FALSE)
    path
}

## Deep-copy the toy job spec as a plain list for mutation-based
## validation tests.
toy_spec_list <- function() {
    unclass(toy_job())
}

as_job <- function(x) {
    class(x) <- "BiocJob"
    x
}
