## End-to-end: run the toy job in a child Rscript process, exactly as a
## developer would from a source checkout.

test_that("runJob executes a job from a source checkout", {
    skip_on_cran()
    mat <- toy_matrix_file()
    workdir <- tempfile("run_")

    result <- runJob(toy_job(),
                     params = list(matrix = mat, method = "none",
                                   center = TRUE),
                     workdir = workdir)

    expect_identical(result$status, 0L)
    expect_true(file.exists(result$outputs[["normalized"]]))

    out <- read.delim(result$outputs[["normalized"]], row.names = 1)
    expect_identical(dim(out), c(4L, 3L))
    ## method=none + center=TRUE => column means are ~0.
    expect_true(all(abs(colMeans(as.matrix(out))) < 1e-12))
})

test_that("runJob surfaces failing jobs", {
    skip_on_cran()
    ## Missing required input => the child process must fail, and the
    ## declared output is reported as missing.
    warnings <- character()
    result <- withCallingHandlers(
        runJob(toy_job(), params = list(), workdir = tempfile("runfail_")),
        warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        })
    expect_false(identical(result$status, 0L))
    expect_true(any(grepl("job exited with status", warnings)))
    expect_true(any(grepl("not produced: normalized", warnings)))
})
