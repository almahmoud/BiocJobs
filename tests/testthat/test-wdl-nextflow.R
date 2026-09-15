## WDL and Nextflow generators.

test_that("wdlTask renders a complete task", {
    text <- wdlTask(toy_job(), image = "example/image:1")
    expect_match(text, "^version 1\\.0\\n", perl = TRUE)
    expect_match(text, "task toy_normalize \\{")
    expect_match(text, "File matrix", fixed = TRUE)
    expect_match(text, "String method = \"log2\"", fixed = TRUE)
    expect_match(text, "Boolean center = false", fixed = TRUE)
    ## float renders as String for exact pass-through
    expect_match(text, "String pseudocount = \"1\"", fixed = TRUE)
    ## values are single-quote-escaped against shell breakage/injection
    expect_match(text, "--matrix '~{sub(matrix, \"'\", \"'", fixed = TRUE)
    expect_match(text, "--normalized 'normalized.tsv'", fixed = TRUE)
    expect_match(text, "File normalized = \"normalized.tsv\"", fixed = TRUE)
    expect_match(text, "docker: \"example/image:1\"", fixed = TRUE)
    expect_match(text, "cpu: 1", fixed = TRUE)
    expect_match(text, "memory: \"1 GB\"", fixed = TRUE)
    expect_match(text, "One of: log2, zscore, none", fixed = TRUE)
    ## Balanced braces.
    expect_identical(lengths(regmatches(text, gregexpr("\\{", text))),
                     lengths(regmatches(text, gregexpr("\\}", text))))
})

test_that("required options have no WDL default; optional inputs guarded", {
    spec <- toy_spec_list()
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "factor", type = "string", required = TRUE, label = "Factor")
    spec$inputs[[1L]]$required <- FALSE
    text <- wdlTask(as_job(spec), image = "x/y:1")
    expect_match(text, "String factor\\n")
    expect_match(text, "File? matrix", fixed = TRUE)
    expect_match(text, "if defined(matrix)", fixed = TRUE)
})

test_that("nextflowModule renders a complete process", {
    text <- nextflowModule(toy_job(), image = "example/image:1")
    expect_match(text, "process TOY_NORMALIZE \\{")
    expect_match(text, "container 'example/image:1'", fixed = TRUE)
    ## nf-core style: file inputs in one meta-led tuple, outputs carry meta.
    expect_match(text, "tuple val(meta), path(matrix)", fixed = TRUE)
    expect_match(text, "val method", fixed = TRUE)
    expect_match(text, "tuple val(meta), path('normalized.tsv'), emit: normalized",
                 fixed = TRUE)
    ## The tag names the unit of work, not the process.
    expect_match(text, "tag \"${meta.id}\"", fixed = TRUE)
    expect_false(grepl("tag \"toy-normalize\"", text, fixed = TRUE))
    expect_match(text, "--matrix '${(matrix as String).replace(", fixed = TRUE)
    expect_match(text, "--normalized 'normalized.tsv'", fixed = TRUE)
    expect_match(text, "cpus 1", fixed = TRUE)
    expect_match(text, "memory '1 GB'", fixed = TRUE)
    ## Continuations are groovy-escaped double backslashes.
    expect_match(text, "\\\\\\\\\\n", perl = TRUE)
    ## Stub touches every output.
    expect_match(text, "stub:", fixed = TRUE)
    expect_match(text, "touch 'normalized.tsv'", fixed = TRUE)
})

test_that("generator files round-trip through the CLI", {
    dir <- tempfile("gen_")
    dir.create(dir)
    nf <- file.path(dir, "toy.nf")
    wdl <- file.path(dir, "toy.wdl")
    nextflowModule(toy_job(), file = nf)
    wdlTask(toy_job(), file = wdl)
    expect_true(all(file.exists(nf, wdl)))
    expect_match(readLines(wdl)[1], "version 1.0", fixed = TRUE)
})

test_that("generators sanitize illegal target identifiers", {
    spec <- toy_spec_list()
    spec$name <- "10x-demux"                    # leading digit
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "in", type = "string", default = "x", label = "reserved word")
    nf <- nextflowModule(as_job(spec), image = "x/y:1")
    expect_match(nf, "process JOB_10X_DEMUX", fixed = TRUE)  # prefixed
    expect_match(nf, "val in_", fixed = TRUE)               # mangled var
    expect_match(nf, "--in ", fixed = TRUE)                 # flag stays literal

    wdl <- wdlTask(as_job(spec), image = "x/y:1")
    expect_match(wdl, "task job_10x_demux", fixed = TRUE)   # valid WDL name
    expect_match(wdl, "String in_", fixed = TRUE)           # 'in' is WDL-reserved too
})

test_that("WDL escapes shell metacharacters and placeholder introducers", {
    spec <- toy_spec_list()
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "note", type = "string", default = "a ~{x} b", label = "n")
    wdl <- wdlTask(as_job(spec), image = "x/y:1")
    ## ~{ in a default is neutralized so the WDL still loads.
    expect_false(grepl('= "a ~{x} b"', wdl, fixed = TRUE))
    expect_match(wdl, "u007E", fixed = TRUE)
    ## every String value on the command line is sub()-escaped.
    expect_match(wdl, "sub(note", fixed = TRUE)
})

test_that("meta = FALSE emits plain paths and tags the first input file", {
    text <- nextflowModule(toy_job(), image = "x/y:1", meta = FALSE)
    expect_match(text, "path matrix", fixed = TRUE)
    expect_match(text, "path 'normalized.tsv', emit: normalized", fixed = TRUE)
    expect_match(text, "tag \"${matrix.name}\"", fixed = TRUE)
    expect_false(grepl("meta", text, fixed = TRUE))
})

test_that("a job with no file inputs still tags and declares meta", {
    spec <- toy_spec_list()
    spec$inputs <- list()
    text <- nextflowModule(as_job(spec), image = "x/y:1")
    expect_match(text, "tuple val(meta)", fixed = TRUE)
    expect_match(text, "tag \"${meta.id}\"", fixed = TRUE)
    ## Without meta there is no file to name, so fall back to the job name.
    plain <- nextflowModule(as_job(spec), image = "x/y:1", meta = FALSE)
    expect_match(plain, "tag \"toy-normalize\"", fixed = TRUE)
})

test_that("a parameter named meta does not collide with the meta map", {
    spec <- toy_spec_list()
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "meta", type = "string", default = "x", label = "Meta")
    text <- nextflowModule(as_job(spec), image = "x/y:1")
    expect_match(text, "val meta_", fixed = TRUE)   # mangled variable
    expect_match(text, "--meta ", fixed = TRUE)     # flag stays literal
})
