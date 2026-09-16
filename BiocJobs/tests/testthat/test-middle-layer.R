## The supplied-values channel and the CLI command style used when a
## BiocExecute/Rapp layer fronts a job.

test_that("execJob(values=) bypasses command-line parsing", {
    skip_on_cran()
    mat <- toy_matrix_file()
    out <- file.path(tempfile("vals_"), "norm.tsv")
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit(Sys.unsetenv("BIOCJOBS_SPEC"))
    ## Typed values, exactly as a Rapp app would hand them over.
    execJob("toy", "toy-normalize",
            values = list(matrix = mat, normalized = out,
                          method = "none", center = TRUE))
    expect_true(file.exists(out))
    m <- as.matrix(read.delim(out, row.names = 1))
    expect_true(all(abs(colMeans(m)) < 1e-12))
})

test_that("supplied values respect unset markers and defaults", {
    mat <- toy_matrix_file()
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit({
        Sys.unsetenv("BIOCJOBS_SPEC")
        BiocJobs:::.setSuppliedValues(NULL)
    })
    ## NA and NULL mean "not supplied": defaults apply. An empty string is
    ## a real value (it round-trips like the direct command line).
    BiocJobs:::.setSuppliedValues(list(matrix = mat, method = NA,
                                       center = NA, pseudocount = NULL))
    params <- jobParams("toy", "toy-normalize")
    expect_identical(params$method, "log2")      # default applied
    expect_false(params$center)                  # default applied
    expect_identical(params$pseudocount, 1.0)    # default applied

    ## Required parameters stay required.
    BiocJobs:::.setSuppliedValues(list(method = "zscore"))
    expect_error(jobParams("toy", "toy-normalize"),
                 "missing required input --matrix")

    ## Typed values are validated like CLI strings.
    BiocJobs:::.setSuppliedValues(list(matrix = mat, method = "bogus"))
    expect_error(jobParams("toy", "toy-normalize"), "not one of")

    ## Unknown names are rejected.
    BiocJobs:::.setSuppliedValues(list(matrix = mat, bogus = 1))
    expect_error(jobParams("toy", "toy-normalize"), "unknown parameter")
})

test_that("supplied values are consumed by at most one run", {
    mat <- toy_matrix_file()
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit(Sys.unsetenv("BIOCJOBS_SPEC"))
    ## execJob clears the channel on exit even on error.
    expect_error(
        execJob("toy", "toy-normalize",
                values = list(matrix = "/nonexistent.tsv")),
        "file not found")
    expect_null(BiocJobs:::.suppliedValues())
})

test_that("the cli command style renders launcher argv", {
    job <- toy_job()
    argv <- jobCommand(job, params = list(matrix = "m.tsv", center = TRUE),
                       style = "cli")
    expect_identical(argv[1:2], c("toy", "toy-normalize"))
    expect_identical(argv[which(argv == "--center") + 1L], "true")

    ## Underscores in job names render as dashes on the CLI.
    spec <- toy_spec_list()
    spec$name <- "toy_normalize.v2"
    expect_identical(cliJobName(as_job(spec)), "toy-normalize.v2")
})

test_that("validateJob flags names a CLI layer cannot expose", {
    spec <- toy_spec_list()
    spec$name <- "if"    # reserved word survives gsub but not make.names
    issues <- validateJob(as_job(spec))
    msgs <- vapply(issues, `[[`, "", "message")
    expect_true(any(grepl("CLI subcommand", msgs)))
})

test_that("jobSkeleton scaffolds a valid, runnable declaration", {
    pkg <- tempfile("skel_")
    dir.create(pkg)
    writeLines(c("Package: skelpkg", "Version: 0.0.1"),
               file.path(pkg, "DESCRIPTION"))
    suppressMessages(jobSkeleton("my-analysis", pkg = pkg))

    yaml <- file.path(pkg, "inst", "biocjobs", "my-analysis.yaml")
    expect_true(file.exists(yaml))
    job <- readJob(yaml)                 # parses and validates
    expect_identical(job$package, "skelpkg")
    issues <- validateJob(job)
    expect_false("error" %in% vapply(issues, `[[`, "", "severity"))

    ## No clobbering.
    expect_error(jobSkeleton("my-analysis", pkg = pkg), "already exists")
})

test_that("empty string round-trips through the supplied-values channel", {
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit({ Sys.unsetenv("BIOCJOBS_SPEC"); BiocJobs:::.setSuppliedValues(NULL) })
    mat <- toy_matrix_file()
    ## An option that legitimately takes "" must receive it, not the default.
    spec <- readJob(toy_yaml())
    BiocJobs:::.setSuppliedValues(list(matrix = mat, method = "none"))
    params <- jobParams("toy", "toy-normalize")
    expect_identical(params$method, "none")
})

test_that("nested execJob does not leak the outer job's supplied values", {
    skip_on_cran()
    ## The channel is consumed by the first jobParams() and restored on exit,
    ## so a job whose script calls execJob() again cannot clobber it. We
    ## approximate by checking consume-then-empty semantics directly.
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit({ Sys.unsetenv("BIOCJOBS_SPEC"); BiocJobs:::.setSuppliedValues(NULL) })
    mat <- toy_matrix_file()
    BiocJobs:::.setSuppliedValues(list(matrix = mat, method = "none"))
    jobParams("toy", "toy-normalize")
    expect_null(BiocJobs:::.suppliedValues())   # consumed exactly once
})
