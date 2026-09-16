## Regression tests for defects found in adversarial review.

test_that("validateJob reports (not crashes on) bare-scalar entries", {
    spec <- toy_spec_list()
    spec$options <- list("verbose")            # '- verbose' in YAML
    issues <- validateJob(as_job(spec))
    msgs <- vapply(issues, `[[`, "", "message")
    expect_true(any(grepl("not a mapping", msgs)))

    spec <- toy_spec_list()
    spec$inputs <- list("counts")
    issues <- validateJob(as_job(spec))
    msgs <- vapply(issues, `[[`, "", "message")
    expect_true(any(grepl("not a mapping", msgs)))
})

test_that("numeric YAML scalars for name/version are normalized", {
    bad <- tempfile(fileext = ".yaml")
    dir.create(file.path(dirname(bad), "scripts"), showWarnings = FALSE)
    script <- file.path(dirname(bad), "scripts", "s.R")
    writeLines("invisible(NULL)", script)
    writeLines(c(
        "biocjobs: '1.0'", "name: 123", "package: x", "title: t",
        "version: 2", paste0("script: scripts/", basename(script)),
        "outputs:", "  - name: out", "    format: tsv", "    label: o"
    ), bad)
    job <- readJob(bad)
    expect_identical(job$name, "123")
    expect_identical(job$version, "2")
})

test_that("jobParams rejects unfilled template placeholders", {
    mat <- toy_matrix_file()
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit(Sys.unsetenv("BIOCJOBS_SPEC"))
    expect_error(
        jobParams("toy", "toy-normalize",
                  args = c("--matrix", mat,
                           "--method", "{{options.method}}")),
        "unfilled template placeholder")
})

test_that("integer options beyond .Machine$integer.max error clearly", {
    int_opt <- list(name = "i", type = "integer")
    expect_error(BiocJobs:::.coerceValue("3000000000", int_opt),
                 "exceeds the integer range")
})

test_that("execJob restores a pre-existing BIOCJOBS_SPEC", {
    skip_on_cran()
    Sys.setenv(BIOCJOBS_SPEC = toy_yaml())
    on.exit(Sys.unsetenv("BIOCJOBS_SPEC"))
    mat <- toy_matrix_file()
    out <- tempfile(fileext = ".tsv")
    owd <- setwd(tempdir()); on.exit(setwd(owd), add = TRUE)
    ## execJob sources the script in-process; args come from this call's
    ## perspective, so run it in a child instead and check env survives.
    status <- system2("Rscript", c(
        "-e", shQuote('BiocJobs::execJob("toy", "toy-normalize")'),
        "--matrix", shQuote(mat), "--normalized", shQuote(out)),
        env = paste0("BIOCJOBS_SPEC=", shQuote(toy_yaml())),
        stdout = FALSE, stderr = FALSE)
    expect_identical(status, 0L)
    expect_identical(Sys.getenv("BIOCJOBS_SPEC"), toy_yaml())
})

test_that("runJob works when the spec path contains spaces", {
    skip_on_cran()
    spaced <- file.path(tempfile("dir with space_"), "toy")
    dir.create(spaced, recursive = TRUE)
    file.copy(list.files(toy_pkg(), full.names = TRUE), spaced,
              recursive = TRUE)
    job <- readJob(file.path(spaced, "inst", "biocjobs", "toy-normalize.yaml"))
    result <- runJob(job,
                     params = list(matrix = toy_matrix_file(),
                                   method = "none",
                                   center = NULL),   # NULLs are skipped
                     workdir = tempfile("run_"))
    expect_identical(result$status, 0L)
    expect_true(file.exists(result$outputs[["normalized"]]))
})

test_that("tesTask default image gets a bootstrap executor, explicit image does not", {
    task <- tesTask(toy_job())
    expect_length(task$executors, 2L)
    boot <- unlist(task$executors[[1L]]$command)
    expect_true(any(grepl("BiocManager::install", boot)))
    expect_true(any(grepl('"BiocJobs", "toy"', boot)))
    expect_identical(task$tags[["biocjobs.template"]], "true")

    task <- tesTask(toy_job(), image = "custom/img:1")
    expect_length(task$executors, 1L)

    ## Fully specified task is not a template.
    mat_urls <- c(matrix = "s3://b/m.tsv")
    task <- tesTask(toy_job(), inputs = mat_urls,
                    outputs = c(normalized = "s3://b/out.tsv"),
                    image = "custom/img:1")
    expect_null(task$tags[["biocjobs.template"]])
})

test_that("depends flow into the bootstrap executor", {
    spec <- toy_spec_list()
    spec$depends <- c("apeglm", "ashr")
    task <- tesTask(as_job(spec))
    boot <- paste(unlist(task$executors[[1L]]$command), collapse = " ")
    expect_match(boot, '"apeglm", "ashr"')
})

test_that("galaxy xref carries the package name verbatim", {
    spec <- toy_spec_list()
    spec$package <- "MixedCase"
    doc <- galaxyTool(as_job(spec), pkg_version = "1.0.0",
                      biocjobs_version = "0.1.0")
    xref <- xml2::xml_find_first(doc, "//xrefs/xref")
    expect_identical(xml2::xml_text(xref), "MixedCase")
})

test_that("writeGalaxyTool stages test-data next to the XML", {
    ## Build a fake package with a test file and a spec that references it.
    root <- tempfile("stagepkg_")
    dir.create(file.path(root, "inst", "biocjobs", "scripts"), recursive = TRUE)
    dir.create(file.path(root, "test-data"))
    writeLines("Package: stub\nVersion: 1.0.0",
               file.path(root, "DESCRIPTION"))
    file.copy(jobScript(toy_job()),
              file.path(root, "inst", "biocjobs", "scripts"))
    writeLines("a\tb", file.path(root, "test-data", "matrix.tsv"))

    spec <- toy_spec_list()
    spec$tests <- list(list(inputs = list(matrix = "test-data/matrix.tsv"),
                            outputs = list(normalized = list())))
    yaml::write_yaml(
        spec[setdiff(names(spec), "_path")],
        file.path(root, "inst", "biocjobs", "toy-normalize.yaml"))
    job <- readJob(file.path(root, "inst", "biocjobs", "toy-normalize.yaml"))

    outdir <- tempfile("galaxyout_")
    dir.create(outdir)
    xmlfile <- file.path(outdir, "tool.xml")
    writeGalaxyTool(galaxyTool(job, biocjobs_version = "0.1.0"), xmlfile,
                    job = job)
    expect_true(file.exists(file.path(outdir, "test-data", "matrix.tsv")))
})

test_that("jobManifest on a jobless package reads DESCRIPTION", {
    root <- tempfile("nojobs_")
    dir.create(root)
    writeLines(c("Package: emptypkg", "Version: 2.5.1"),
               file.path(root, "DESCRIPTION"))
    m <- jobManifest(root)
    expect_identical(m$package, "emptypkg")
    expect_identical(m$version, "2.5.1")
    expect_length(m$jobs, 0L)
})
