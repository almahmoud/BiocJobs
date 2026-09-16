test_that("galaxyTool generates a complete wrapper", {
    doc <- galaxyTool(toy_job(), biocjobs_version = "0.1.0")
    root <- xml2::xml_root(doc)

    expect_identical(xml2::xml_name(root), "tool")
    expect_identical(xml2::xml_attr(root, "id"), "biocjobs_toy_toy_normalize")
    ## host package version leads; job spec version in the suffix
    expect_identical(xml2::xml_attr(root, "version"), "1.2.3+biocjobs1.0.0")
    expect_identical(xml2::xml_attr(root, "profile"), "23.0")

    ## The container is the entry way: one <container>, no bioconda
    ## <requirement type="package"> entries.
    cont <- xml2::xml_find_all(doc, "//requirements/container")
    expect_length(cont, 1L)
    expect_identical(xml2::xml_attr(cont, "type"), "docker")
    expect_match(xml2::xml_text(cont), "^bioconductor/bioconductor_docker:")
    expect_length(xml2::xml_find_all(doc, "//requirements/requirement"), 0L)

    ## Bioconductor xref.
    xref <- xml2::xml_find_first(doc, "//xrefs/xref")
    expect_identical(xml2::xml_text(xref), "toy")
    expect_identical(xml2::xml_attr(xref, "type"), "bioconductor")

    ## Command: canonical invocation with one --flag '$var' pair per param.
    cmd <- xml2::xml_text(xml2::xml_find_first(doc, "//command"))
    expect_match(cmd, 'BiocJobs::execJob\\("toy", "toy-normalize"\\)',
                 fixed = FALSE)
    expect_match(cmd, "--matrix '\\$matrix'")
    expect_match(cmd, "--method '\\$method'")
    expect_match(cmd, "--center \\$center")
    expect_match(cmd, "--pseudocount \\$pseudocount")
    expect_match(cmd, "--normalized '\\$normalized'")
    expect_identical(
        xml2::xml_attr(xml2::xml_find_first(doc, "//command"),
                       "detect_errors"),
        "exit_code")

    ## Input file param.
    p <- xml2::xml_find_first(doc, "//inputs/param[@name='matrix']")
    expect_identical(xml2::xml_attr(p, "type"), "data")
    expect_identical(xml2::xml_attr(p, "format"), "tabular")

    ## Choice -> select with the default selected.
    sel <- xml2::xml_find_first(doc, "//inputs/param[@name='method']")
    expect_identical(xml2::xml_attr(sel, "type"), "select")
    opts <- xml2::xml_find_all(sel, "option")
    expect_identical(xml2::xml_attr(opts, "value"),
                     c("log2", "zscore", "none"))
    expect_identical(xml2::xml_attr(opts, "selected"),
                     c("true", NA, NA))

    ## Boolean with checked state from the default.
    b <- xml2::xml_find_first(doc, "//inputs/param[@name='center']")
    expect_identical(xml2::xml_attr(b, "type"), "boolean")
    expect_identical(xml2::xml_attr(b, "truevalue"), "true")
    expect_identical(xml2::xml_attr(b, "falsevalue"), "false")
    expect_identical(xml2::xml_attr(b, "checked"), "false")

    ## Float with default value.
    f <- xml2::xml_find_first(doc, "//inputs/param[@name='pseudocount']")
    expect_identical(xml2::xml_attr(f, "type"), "float")
    expect_identical(xml2::xml_attr(f, "value"), "1")

    ## Output dataset.
    out <- xml2::xml_find_first(doc, "//outputs/data[@name='normalized']")
    expect_identical(xml2::xml_attr(out, "format"), "tabular")
})

test_that("string options can extend the Galaxy sanitizer", {
    spec <- toy_spec_list()
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "design", type = "string", default = "~ condition",
        label = "Design formula", allow_chars = list("~")
    )
    doc <- galaxyTool(as_job(spec), biocjobs_version = "0.1.0")
    add <- xml2::xml_find_first(
        doc, "//param[@name='design']/sanitizer/valid/add")
    expect_identical(xml2::xml_attr(add, "value"), "~")
})

test_that("spec tests become Galaxy test cases", {
    spec <- toy_spec_list()
    spec$tests <- list(list(
        inputs = list(matrix = "test-data/matrix.tsv"),
        options = list(method = "none", center = TRUE),
        outputs = list(normalized = list(file = "test-data/normalized.tsv",
                                         compare = "sim_size",
                                         delta = 200))
    ))
    doc <- galaxyTool(as_job(spec), biocjobs_version = "0.1.0")
    tst <- xml2::xml_find_first(doc, "//tests/test")
    expect_false(inherits(tst, "xml_missing"))
    p <- xml2::xml_find_first(tst, "param[@name='matrix']")
    expect_identical(xml2::xml_attr(p, "value"), "matrix.tsv")
    b <- xml2::xml_find_first(tst, "param[@name='center']")
    expect_identical(xml2::xml_attr(b, "value"), "true")
    o <- xml2::xml_find_first(tst, "output[@name='normalized']")
    expect_identical(xml2::xml_attr(o, "file"), "normalized.tsv")
    expect_identical(xml2::xml_attr(o, "compare"), "sim_size")
    expect_identical(xml2::xml_attr(o, "delta"), "200")
})

test_that("citations render as DOI entries", {
    spec <- toy_spec_list()
    spec$citations <- list(list(doi = "10.1000/example.doi"))
    doc <- galaxyTool(as_job(spec), biocjobs_version = "0.1.0")
    ci <- xml2::xml_find_first(doc, "//citations/citation")
    expect_identical(xml2::xml_text(ci), "10.1000/example.doi")
    expect_identical(xml2::xml_attr(ci, "type"), "doi")
})

test_that("the wrapper file writes and re-parses", {
    doc <- galaxyTool(toy_job(), biocjobs_version = "0.1.0")
    file <- tempfile(fileext = ".xml")
    writeGalaxyTool(doc, file)
    reread <- xml2::read_xml(file)
    expect_identical(xml2::xml_name(reread), "tool")
})

test_that("a declared container becomes the Galaxy requirement", {
    spec <- toy_spec_list()
    spec$container <- "ghcr.io/almahmoud/deseq2:devel"
    doc <- galaxyTool(as_job(spec), biocjobs_version = "0.1.0")
    cont <- xml2::xml_find_first(doc, "//requirements/container")
    expect_identical(xml2::xml_text(cont), "ghcr.io/almahmoud/deseq2:devel")
    ## An explicit image argument wins over the spec.
    doc2 <- galaxyTool(as_job(spec), biocjobs_version = "0.1.0",
                       image = "example/other:2")
    expect_identical(
        xml2::xml_text(xml2::xml_find_first(doc2, "//requirements/container")),
        "example/other:2")
})

test_that("the tool carries a provenance header", {
    doc <- galaxyTool(toy_job(), biocjobs_version = "0.1.0")
    txt <- as.character(doc)
    expect_match(txt, "Generated by BiocJobs 0.1.0", fixed = TRUE)
    expect_match(txt, "Do not edit", fixed = TRUE)
})
