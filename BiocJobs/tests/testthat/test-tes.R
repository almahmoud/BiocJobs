test_that("tesTask maps the job onto a TES 1.1 task", {
    task <- tesTask(toy_job(), image = "example/image:1")
    expect_s3_class(task, "TesTask")

    expect_identical(task$name, "toy/toy-normalize")
    expect_length(task$executors, 1L)
    ex <- task$executors[[1L]]
    expect_identical(ex$image, "example/image:1")
    expect_identical(ex$command[[1L]], "Rscript")
    expect_identical(ex$command[[2L]], "-e")
    expect_identical(ex$command[[3L]],
                     'BiocJobs::execJob("toy", "toy-normalize")')

    ## Inputs/outputs staged at fixed container paths.
    expect_identical(task$inputs[[1L]]$path,
                     "/tmp/biocjob/inputs/matrix.tsv")
    expect_identical(task$inputs[[1L]]$type, "FILE")
    expect_identical(task$outputs[[1L]]$path,
                     "/tmp/biocjob/outputs/normalized.tsv")

    ## URL placeholders when not supplied.
    expect_identical(task$inputs[[1L]]$url, "{{inputs.matrix.url}}")
    expect_identical(task$outputs[[1L]]$url, "{{outputs.normalized.url}}")

    ## Resources from the spec.
    expect_identical(task$resources$cpu_cores, 1L)
    expect_identical(task$resources$ram_gb, 1)

    ## Command carries container paths and option defaults.
    cmd <- unlist(ex$command)
    expect_true("--matrix" %in% cmd)
    expect_identical(cmd[which(cmd == "--matrix") + 1L],
                     "/tmp/biocjob/inputs/matrix.tsv")
    expect_identical(cmd[which(cmd == "--method") + 1L], "log2")
    expect_identical(cmd[which(cmd == "--center") + 1L], "false")

    ## Tags identify the provenance.
    expect_identical(task$tags[["biocjobs.package"]], "toy")
    expect_identical(task$tags[["biocjobs.job"]], "toy-normalize")
})

test_that("tesTask honours supplied URLs and option values", {
    task <- tesTask(toy_job(),
                    inputs = c(matrix = "s3://bucket/m.tsv"),
                    outputs = c(normalized = "s3://bucket/out/norm.tsv"),
                    options = list(method = "zscore"),
                    image = "example/image:1")
    expect_identical(task$inputs[[1L]]$url, "s3://bucket/m.tsv")
    expect_identical(task$outputs[[1L]]$url, "s3://bucket/out/norm.tsv")
    cmd <- unlist(task$executors[[1L]]$command)
    expect_identical(cmd[which(cmd == "--method") + 1L], "zscore")
})

test_that("default container derives from the Bioconductor release", {
    task <- tesTask(toy_job())
    expect_match(task$executors[[1L]]$image,
                 "^bioconductor/bioconductor_docker:RELEASE_")
})

test_that("writeTesTask emits valid JSON that round-trips", {
    task <- tesTask(toy_job(), image = "example/image:1")
    file <- tempfile(fileext = ".json")
    writeTesTask(task, file)
    parsed <- jsonlite::read_json(file)
    expect_identical(parsed$name, "toy/toy-normalize")
    expect_identical(parsed$executors[[1L]]$image, "example/image:1")
    ## Executor command must serialize as a JSON array of strings.
    expect_true(is.list(parsed$executors[[1L]]$command))
    expect_true(length(parsed$executors[[1L]]$command) > 3L)
})
