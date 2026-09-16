## jobParams() resolves the spec via BIOCJOBS_SPEC in these tests, exactly
## as it does under runJob() and during package development.

with_toy_spec <- function(code) {
    withr_like <- Sys.getenv("BIOCJOBS_SPEC", unset = NA)
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit({
        if (is.na(withr_like)) Sys.unsetenv("BIOCJOBS_SPEC")
        else Sys.setenv(BIOCJOBS_SPEC = withr_like)
    })
    force(code)
}

test_that("jobParams parses, coerces and defaults", {
    mat <- toy_matrix_file()
    out <- file.path(tempfile("outs_"), "norm.tsv")
    with_toy_spec({
        params <- jobParams("toy", "toy-normalize",
                            args = c("--matrix", mat,
                                     "--normalized", out,
                                     "--method", "zscore",
                                     "--center", "true"))
        expect_identical(params$matrix, mat)
        expect_identical(params$normalized, out)
        expect_identical(params$method, "zscore")
        expect_true(params$center)
        expect_identical(params$pseudocount, 1.0)   # default applied
        expect_true(dir.exists(dirname(out)))       # parent dir created
        expect_s3_class(attr(params, "job"), "BiocJob")
    })
})

test_that("jobParams supports --name=value syntax", {
    mat <- toy_matrix_file()
    with_toy_spec({
        params <- jobParams("toy", "toy-normalize",
                            args = c(paste0("--matrix=", mat),
                                     "--method=none"))
        expect_identical(params$method, "none")
    })
})

test_that("outputs default to <name>.<extension>", {
    mat <- toy_matrix_file()
    with_toy_spec({
        params <- jobParams("toy", "toy-normalize", args = c("--matrix", mat))
        expect_identical(params$normalized, "normalized.tsv")
    })
})

test_that("jobParams rejects bad invocations", {
    mat <- toy_matrix_file()
    with_toy_spec({
        expect_error(jobParams("toy", "toy-normalize", args = character()),
                     "missing required input --matrix")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", "/nonexistent/f.tsv")),
                     "file not found")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", mat, "--bogus", "1")),
                     "unknown parameter")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", mat, "--method", "sqrt")),
                     "not one of")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", mat, "--center", "maybe")),
                     "expected a boolean")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", mat,
                                        "--pseudocount", "abc")),
                     "expected a number")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix", mat, "--matrix", mat)),
                     "more than once")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("--matrix")),
                     "missing a value")
        expect_error(jobParams("toy", "toy-normalize",
                               args = c("stray", "--matrix", mat)),
                     "expected --name value")
    })
})

test_that("boolean and integer coercion accept common spellings", {
    bool_opt <- list(name = "b", type = "boolean")
    expect_true(BiocJobs:::.coerceValue("TRUE", bool_opt))
    expect_true(BiocJobs:::.coerceValue("yes", bool_opt))
    expect_true(BiocJobs:::.coerceValue("1", bool_opt))
    expect_false(BiocJobs:::.coerceValue("No", bool_opt))

    int_opt <- list(name = "i", type = "integer")
    expect_identical(BiocJobs:::.coerceValue("42", int_opt), 42L)
    expect_error(BiocJobs:::.coerceValue("4.5", int_opt), "expected an integer")
})

test_that("numeric option bounds are enforced at runtime", {
    lo <- list(name = "a", type = "float", min = 0, max = 1)
    expect_identical(BiocJobs:::.coerceValue("0.5", lo), 0.5)
    expect_error(BiocJobs:::.coerceValue("1.5", lo), "above the maximum")
    expect_error(BiocJobs:::.coerceValue("-0.1", lo), "below the minimum")
    hi <- list(name = "n", type = "integer", min = 1)
    expect_error(BiocJobs:::.coerceValue("0", hi), "below the minimum")
})
