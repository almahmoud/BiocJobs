## The CLI dispatcher returns an exit status instead of quitting, so it can
## be exercised in-process.

cli <- function(...) suppressMessages(BiocJobs:::.cliDispatch(c(...)))
toy <- system.file("examples", "toy", package = "BiocJobs")

test_that("discovery, validation and help succeed on the toy package", {
    out <- capture.output(status <- cli("list", toy))
    expect_identical(status, 0L)
    expect_true(any(grepl("BiocJob 'toy-normalize'", out, fixed = TRUE)))
    expect_identical(cli("validate", toy), 0L)
    expect_identical(cli("help"), 0L)
})

test_that("every generator writes its --out file", {
    dir <- tempfile("cli_")
    dir.create(dir)
    for (cmd in c("tes", "galaxy", "nextflow", "wdl", "htcondor")) {
        out <- file.path(dir, paste0("toy.", cmd))
        expect_identical(cli(cmd, toy, "toy-normalize", "--out", out), 0L)
        expect_true(file.exists(out), info = cmd)
    }
    manifest <- file.path(dir, "manifest.json")
    expect_identical(cli("manifest", toy, "--out", manifest), 0L)
    expect_true(file.exists(manifest))
    ## --image reaches the generated artifact.
    out <- file.path(dir, "pinned.nf")
    cli("nextflow", toy, "toy-normalize", "--out", out,
        "--image", "example.org/toy@sha256:0")
    expect_true(any(grepl("example.org/toy@sha256:0", readLines(out),
                          fixed = TRUE)))
})

test_that("failures are reported as a non-zero status or an error", {
    bad <- tempfile("badpkg_")
    dir.create(bad)
    file.copy(list.files(toy, full.names = TRUE), bad, recursive = TRUE)
    yaml <- file.path(bad, "inst", "biocjobs", "toy-normalize.yaml")
    writeLines(sub("^script: .*", "script: scripts/missing.R",
                   readLines(yaml)), yaml)
    expect_identical(cli("validate", bad), 1L)
    expect_error(cli("nextflow", toy), "needs a job name")
    expect_error(cli("nextflow", toy, "no-such-job"))
    expect_error(cli("frobnicate", toy))
})
