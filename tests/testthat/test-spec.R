test_that("readJob parses the toy specification", {
    job <- toy_job()
    expect_s3_class(job, "BiocJob")
    expect_identical(job$name, "toy-normalize")
    expect_identical(job$package, "toy")
    expect_length(job$inputs, 1L)
    expect_length(job$outputs, 1L)
    expect_length(job$options, 3L)
    expect_identical(as.character(job$options[[1L]]$choices),
                     c("log2", "zscore", "none"))
})

test_that("findJobs discovers jobs in source and installed layouts", {
    jobs <- findJobs(toy_pkg())
    expect_named(jobs, "toy-normalize")

    ## Installed layout: biocjobs/ directly under the package root.
    fake <- tempfile("installed_")
    dir.create(file.path(fake, "biocjobs", "scripts"), recursive = TRUE)
    file.copy(file.path(toy_pkg(), "DESCRIPTION"), fake)
    file.copy(toy_yaml(), file.path(fake, "biocjobs"))
    file.copy(file.path(dirname(toy_yaml()), "scripts", "toy-normalize.R"),
              file.path(fake, "biocjobs", "scripts"))
    jobs <- findJobs(fake)
    expect_named(jobs, "toy-normalize")

    ## No jobs at all.
    empty <- tempfile("empty_")
    dir.create(empty)
    expect_length(findJobs(empty), 0L)
})

test_that("jobScript resolves the script next to the spec", {
    expect_true(file.exists(jobScript(toy_job())))
})

test_that("validateJob passes the toy spec", {
    issues <- validateJob(toy_job())
    severities <- vapply(issues, `[[`, "", "severity")
    expect_false("error" %in% severities)
})

test_that("validateJob catches structural errors", {
    errors_of <- function(spec) {
        issues <- validateJob(as_job(spec))
        vapply(issues, `[[`, "", "message")[
            vapply(issues, `[[`, "", "severity") == "error"]
    }

    spec <- toy_spec_list()
    spec$name <- NULL
    expect_match(paste(errors_of(spec), collapse = "; "),
                 "missing required field 'name'")

    spec <- toy_spec_list()
    spec$name <- "Bad Name!"
    expect_match(paste(errors_of(spec), collapse = "; "), "must match")

    spec <- toy_spec_list()
    spec$outputs <- list()
    expect_match(paste(errors_of(spec), collapse = "; "), "no outputs")

    spec <- toy_spec_list()
    spec$options[[1L]]$default <- "not-a-choice"
    expect_match(paste(errors_of(spec), collapse = "; "),
                 "not among the declared choices")

    spec <- toy_spec_list()
    spec$options[[1L]]$type <- "enum"
    expect_match(paste(errors_of(spec), collapse = "; "),
                 "'type' must be one of")

    ## Duplicate names across sections share one CLI flag namespace.
    spec <- toy_spec_list()
    spec$options[[2L]]$name <- "matrix"
    expect_match(paste(errors_of(spec), collapse = "; "), "duplicate")

    ## Option with neither default nor required.
    spec <- toy_spec_list()
    spec$options[[3L]]$default <- NULL
    expect_match(paste(errors_of(spec), collapse = "; "),
                 "either a 'default' or 'required: true'")

    spec <- toy_spec_list()
    spec$resources$cpus <- -2
    expect_match(paste(errors_of(spec), collapse = "; "),
                 "positive number")
})

test_that("readJob rejects an invalid spec file", {
    bad <- tempfile(fileext = ".yaml")
    writeLines(c("biocjobs: '1.0'", "name: no-outputs", "package: x",
                 "title: t", "script: missing.R"), bad)
    expect_error(readJob(bad), "invalid job specification")
})

test_that("unknown formats validate as notes, not errors", {
    spec <- toy_spec_list()
    spec$inputs[[1L]]$format <- "frobnicated"
    issues <- validateJob(as_job(spec))
    severities <- vapply(issues, `[[`, "", "severity")
    messages <- vapply(issues, `[[`, "", "message")
    expect_false("error" %in% severities)
    expect_true(any(grepl("frobnicated", messages)))
})

test_that("loom is a known format and maps to the Galaxy datatype", {
    fmt <- jobFormats()
    loom <- fmt[fmt$format == "loom", ]
    expect_identical(nrow(loom), 1L)
    expect_identical(loom$galaxy, "loom")
    expect_identical(loom$extension, "loom")
    ## A spec declaring it validates without the unknown-format note.
    spec <- toy_spec_list()
    spec$outputs[[1L]]$format <- "loom"
    issues <- validateJob(as_job(spec))
    msgs <- vapply(issues, `[[`, "", "message")
    expect_false(any(grepl("not in jobFormats", msgs)))
    ## and the output file gets the right extension.
    expect_identical(BiocJobs:::.defaultFileName("counts", "loom"),
                     "counts.loom")
})
