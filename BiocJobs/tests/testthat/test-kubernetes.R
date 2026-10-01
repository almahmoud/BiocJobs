k8s_pod <- function(x) x$spec$template$spec
k8s_command <- function(x) unlist(k8s_pod(x)$containers[[1L]]$command)
flag_value <- function(cmd, flag) cmd[which(cmd == paste0("--", flag)) + 1L]

test_that("kubernetesJob maps the job onto a batch/v1 Job", {
    x <- kubernetesJob(toy_job(), image = "example/image:1")
    expect_s3_class(x, "KubernetesJob")
    expect_identical(x$apiVersion, "batch/v1")
    expect_identical(x$kind, "Job")
    expect_identical(x$metadata$generateName, "toy-normalize-")
    expect_identical(x$metadata$labels, list(
        `app.kubernetes.io/managed-by` = "BiocJobs",
        `biocjobs.package` = "toy",
        `biocjobs.job` = "toy-normalize"))
    expect_identical(x$spec$template$metadata$labels, x$metadata$labels)
    expect_identical(x$metadata$annotations$biocjobs.spec, "1.0")
    expect_identical(x$spec$backoffLimit, 0L)

    pod <- k8s_pod(x)
    expect_identical(pod$restartPolicy, "Never")
    expect_false(pod$automountServiceAccountToken)
    expect_length(pod$containers, 1L)
    main <- pod$containers[[1L]]
    expect_identical(main$name, "job")
    expect_identical(main$image, "example/image:1")
    expect_identical(main$workingDir, "/biocjob")
    expect_false(main$securityContext$allowPrivilegeEscalation)
    expect_identical(main$volumeMounts,
                     list(list(name = "work", mountPath = "/biocjob")))
    expect_identical(pod$volumes, list(list(
        name = "work", emptyDir = list(sizeLimit = "1Gi"))))
})

test_that("the command is the canonical argv with container paths", {
    x <- kubernetesJob(toy_job(), image = "example/image:1",
                       options = list(center = TRUE))
    cmd <- k8s_command(x)
    expect_identical(cmd[1:3], c("Rscript", "-e",
                                 'BiocJobs::execJob("toy", "toy-normalize")'))
    expect_identical(flag_value(cmd, "matrix"),
                     "/biocjob/inputs/matrix.tsv")
    expect_identical(flag_value(cmd, "normalized"),
                     "/biocjob/outputs/normalized.tsv")
    expect_identical(flag_value(cmd, "method"), "log2")
    expect_identical(flag_value(cmd, "center"), "true")
    expect_identical(flag_value(cmd, "pseudocount"), "1")
    expect_type(k8s_pod(x)$containers[[1L]]$command, "list")
})

test_that("each input is staged by an init container", {
    url <- "https://example.org/data/m.tsv"
    x <- kubernetesJob(toy_job(), inputs = c(matrix = url),
                       image = "example/image:1")
    init <- k8s_pod(x)$initContainers
    expect_length(init, 1L)
    expect_identical(init[[1L]]$name, "stage-matrix")
    expect_identical(init[[1L]]$image, "example/image:1")
    expect_identical(unlist(init[[1L]]$command),
                     c("curl", "-fsSL", "--create-dirs", "-o",
                       "/biocjob/inputs/matrix.tsv", url))
    expect_identical(init[[1L]]$volumeMounts,
                     k8s_pod(x)$containers[[1L]]$volumeMounts)
    expect_null(x$metadata$annotations$biocjobs.template)
})

test_that("a custom workdir moves every path", {
    x <- kubernetesJob(toy_job(), image = "example/image:1",
                       workdir = "/data/run")
    main <- k8s_pod(x)$containers[[1L]]
    expect_identical(main$workingDir, "/data/run")
    expect_identical(main$volumeMounts[[1L]]$mountPath, "/data/run")
    expect_identical(flag_value(unlist(main$command), "normalized"),
                     "/data/run/outputs/normalized.tsv")
    expect_identical(unlist(k8s_pod(x)$initContainers[[1L]]$command)[5L],
                     "/data/run/inputs/matrix.tsv")
})

test_that("unknown values become placeholders and mark a template", {
    spec <- toy_spec_list()
    spec$options[[length(spec$options) + 1L]] <- list(
        name = "factor", type = "string", required = TRUE, label = "Factor")
    x <- kubernetesJob(as_job(spec), image = "example/image:1")
    expect_identical(unlist(k8s_pod(x)$initContainers[[1L]]$command)[6L],
                     "{{inputs.matrix.url}}")
    expect_identical(flag_value(k8s_command(x), "factor"),
                     "{{options.factor}}")
    expect_identical(x$metadata$annotations$biocjobs.template, "true")

    filled <- kubernetesJob(as_job(spec),
                            inputs = c(matrix = "ftp://example.org/m.tsv"),
                            options = list(factor = "condition"),
                            image = "example/image:1")
    expect_identical(flag_value(k8s_command(filled), "factor"), "condition")
    expect_null(filled$metadata$annotations$biocjobs.template)
})

test_that("resources are Kubernetes quantity strings", {
    main <- k8s_pod(kubernetesJob(toy_job(), image = "x/y:1"))$containers
    expect_identical(main[[1L]]$resources, list(
        requests = list(cpu = "1", memory = "1Gi",
                        `ephemeral-storage` = "1Gi"),
        limits = list(memory = "1Gi")))

    spec <- toy_spec_list()
    spec$resources <- list(cpus = 0.5, memory_gb = 1.5)
    pod <- k8s_pod(kubernetesJob(as_job(spec), image = "x/y:1"))
    expect_identical(pod$containers[[1L]]$resources, list(
        requests = list(cpu = "0.5", memory = "1.5Gi"),
        limits = list(memory = "1.5Gi")))
    expect_length(pod$volumes[[1L]]$emptyDir, 0L)

    spec$resources <- list()
    pod <- k8s_pod(kubernetesJob(as_job(spec), image = "x/y:1"))
    expect_null(pod$containers[[1L]]$resources)
})

test_that("names are DNS-safe and within Kubernetes limits", {
    spec <- toy_spec_list()
    spec$name <- paste0("x_", strrep("long.", 20L), "job-")
    spec$inputs[[1L]]$name <- "raw_matrix"
    x <- kubernetesJob(as_job(spec), image = "x/y:1")
    name <- x$metadata$generateName
    expect_match(name, "^[a-z0-9]([-a-z0-9]*[a-z0-9])?-$")
    expect_lte(nchar(name), 58L)
    for (value in x$metadata$labels) {
        expect_lte(nchar(value), 63L)
        expect_match(value, "^[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$")
    }
    expect_identical(k8s_pod(x)$initContainers[[1L]]$name,
                     "stage-raw-matrix")
})

test_that("the image is the argument, then the container, and required", {
    job <- toy_job()
    job$container <- "c/d:2"
    x <- kubernetesJob(job)
    expect_identical(k8s_pod(x)$containers[[1L]]$image, "c/d:2")
    expect_identical(k8s_pod(x)$initContainers[[1L]]$image, "c/d:2")
    expect_identical(k8s_pod(kubernetesJob(job, image = "a/b:1"))$
                         containers[[1L]]$image, "a/b:1")
    job$container <- NULL
    expect_error(kubernetesJob(job), "declare 'container:'")
})

test_that("an optional input without a URL is left out", {
    spec <- toy_spec_list()
    spec$inputs[[2L]] <- list(name = "extra", format = "tsv",
                              required = FALSE)
    x <- kubernetesJob(as_job(spec), inputs = c(matrix = "https://x/m.tsv"),
                       image = "x/y:1")
    init <- k8s_pod(x)$initContainers
    expect_identical(vapply(init, `[[`, "", "name"), "stage-matrix")
    expect_false("--extra" %in% k8s_command(x))
    expect_null(x$metadata$annotations$biocjobs.template)

    x <- kubernetesJob(as_job(spec), image = "x/y:1",
                       inputs = c(matrix = "https://x/m.tsv",
                                  extra = "https://x/e.tsv"))
    expect_length(k8s_pod(x)$initContainers, 2L)
    expect_identical(flag_value(k8s_command(x), "extra"),
                     "/biocjob/inputs/extra.tsv")
})

test_that("claim mounts a PersistentVolumeClaim as the work volume", {
    x <- kubernetesJob(toy_job(), image = "x/y:1", claim = "toy-results")
    expect_identical(k8s_pod(x)$volumes, list(list(
        name = "work",
        persistentVolumeClaim = list(claimName = "toy-results"))))
    expect_error(kubernetesJob(toy_job(), image = "x/y:1", claim = "a b"),
                 "PersistentVolumeClaim")
})

test_that("unknown names and unsupported URLs are rejected", {
    job <- toy_job()
    expect_error(kubernetesJob(job, inputs = c(counts = "https://x/y")),
                 "unknown input(s): counts", fixed = TRUE)
    expect_error(kubernetesJob(job, options = list(metod = "none")),
                 "unknown option(s): metod", fixed = TRUE)
    expect_error(kubernetesJob(job, inputs = "https://x/y"),
                 "must be named")
    expect_error(kubernetesJob(job, inputs = c(matrix = "s3://b/m.tsv")),
                 "http, https or ftp: matrix")
    expect_error(kubernetesJob(job, inputs = c(matrix = "--config=/x")),
                 "http, https or ftp")
})

test_that("writeKubernetesJob emits YAML that round-trips", {
    x <- kubernetesJob(toy_job(), image = "example/image:1")
    text <- writeKubernetesJob(x)
    lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    expect_match(lines[1L], "^# Generated by BiocJobs .* 'toy-normalize' job")
    expect_match(lines[3L], "biocjobsCLI()' kubernetes <pkg> toy-normalize",
                 fixed = TRUE)
    expect_true("  backoffLimit: 0" %in% lines)
    expect_true("      automountServiceAccountToken: false" %in% lines)

    file <- tempfile(fileext = ".yaml")
    expect_identical(writeKubernetesJob(x, file), text)
    parsed <- yaml::read_yaml(file)
    expect_identical(parsed$metadata, unclass(x)$metadata)
    pod <- parsed$spec$template$spec
    expect_identical(parsed$spec$backoffLimit, 0L)
    expect_false(pod$automountServiceAccountToken)
    expect_identical(pod$containers[[1L]]$command, k8s_command(x))
    expect_identical(pod$containers[[1L]]$resources$requests$cpu, "1")
    expect_identical(pod$initContainers[[1L]]$command[[6L]],
                     "{{inputs.matrix.url}}")
    expect_identical(pod$volumes[[1L]]$emptyDir$sizeLimit, "1Gi")
})

test_that("an empty emptyDir is written as a mapping", {
    spec <- toy_spec_list()
    spec$resources <- list()
    text <- writeKubernetesJob(kubernetesJob(as_job(spec), image = "x/y:1"))
    expect_match(text, "emptyDir: {}", fixed = TRUE)
})

test_that("kubernetesJob writes the manifest when given a file", {
    file <- tempfile(fileext = ".yaml")
    x <- withVisible(kubernetesJob(toy_job(), image = "x/y:1", file = file))
    expect_false(x$visible)
    expect_s3_class(x$value, "KubernetesJob")
    expect_identical(readLines(file),
                     strsplit(writeKubernetesJob(x$value), "\n")[[1L]])
})

test_that("the kubernetes CLI command honours --out, --image and --claim", {
    cli <- function(...) suppressMessages(BiocJobs:::.cliDispatch(c(...)))
    out <- tempfile(fileext = ".k8s.yaml")
    image <- "example.org/toy@sha256:0"
    expect_identical(cli("kubernetes", toy_pkg(), "toy-normalize",
                         "--out", out, "--image", image), 0L)
    parsed <- yaml::read_yaml(out)
    pod <- parsed$spec$template$spec
    expect_identical(pod$containers[[1L]]$image, image)
    expect_identical(pod$initContainers[[1L]]$image, image)

    printed <- capture.output(cli("kubernetes", toy_pkg(), "toy-normalize",
                                  "--image", image, "--claim", "results"))
    expect_true("kind: Job" %in% printed)
    expect_true(any(grepl("^ +claimName: results$", printed)))
    expect_error(cli("kubernetes", toy_pkg()), "needs a job name")
    expect_error(cli("kubernetes", toy_pkg(), "toy-normalize",
                     "--image", image, "--matrix", "https://x/m.tsv"),
                 "does not accept --matrix; fill inputs and options with",
                 fixed = TRUE)
})

test_that("label values and the header cannot carry other characters", {
    expect_identical(BiocJobs:::.labelValue("toy\n---\nkind: Secret"),
                     "toy-----kind--Secret")
    job <- toy_job()
    job$package <- "toy\n---\nkind: Secret"
    expect_error(kubernetesJob(job, image = "img"),
                 "'package' must be an R package name", fixed = TRUE)
    text <- writeKubernetesJob(kubernetesJob(toy_job(), image = "img"))
    lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    expect_true(all(startsWith(lines[1:3], "# ")))
    expect_identical(yaml::yaml.load(text)$kind, "Job")
})

