## Package-level job manifest.
##
## The manifest is the aggregation unit for build infrastructure: for each
## package it enumerates every declared job with its full interface, so a
## registry of dispatchable jobs across all of Bioconductor can be built by
## concatenating per-package manifests — no package installation or code
## evaluation required.

#' Build a job manifest for a package
#'
#' Summarizes every job declared by a package into a single machine-readable
#' structure, suitable for aggregation into a Bioconductor-wide job registry.
#'
#' @param pkg Package source directory, installed package directory, or
#'   installed package name (see [findJobs()]).
#' @param file Optional path; when supplied the manifest is written as JSON.
#' @return A list with elements `package`, `version`, `biocjobs` (spec
#'   version) and `jobs`; class `"BiocJobManifest"`.
#' @examples
#' toy <- system.file("examples", "toy", package = "BiocJobs")
#' manifest <- jobManifest(toy)
#'
#' ## Registry-facing identity: package, version, and the declared jobs.
#' manifest$package
#' manifest$version
#' vapply(manifest$jobs, `[[`, "", "name")
#'
#' ## Each entry carries the full typed interface plus the canonical
#' ## command a dispatcher would run.
#' job <- manifest$jobs[[1]]
#' str(job$options[[1]])
#' cat(paste(unlist(job$command), collapse = " "), "\n")
#'
#' ## Written as JSON, per-package manifests concatenate into a registry.
#' path <- file.path(tempdir(), "toy-manifest.json")
#' invisible(jobManifest(toy, file = path))
#' cat(head(readLines(path), 8), sep = "\n")
#' @export
jobManifest <- function(pkg = ".", file = NULL) {
    jobs <- findJobs(pkg)

    ## Identify the package from its DESCRIPTION even when it declares no
    ## jobs, so aggregated registries carry real names/versions throughout.
    pkg_name <- if (length(jobs)) jobs[[1L]]$package else NULL
    pkg_version <- if (length(jobs)) .hostPkgVersion(jobs[[1L]]) else NULL
    if (is.null(pkg_name) || is.null(pkg_version)) {
        desc_path <- file.path(.pkgRoot(pkg), "DESCRIPTION")
        if (file.exists(desc_path)) {
            dcf <- read.dcf(desc_path)
            if (is.null(pkg_name) && "Package" %in% colnames(dcf))
                pkg_name <- unname(dcf[1L, "Package"])
            if (is.null(pkg_version) && "Version" %in% colnames(dcf))
                pkg_version <- unname(dcf[1L, "Version"])
        }
    }

    manifest <- list(
        package = pkg_name %||% basename(normalizePath(pkg, mustWork = FALSE)),
        version = pkg_version,
        biocjobs = .SPEC_VERSION,
        jobs = lapply(unname(jobs), function(job) {
            list(
                name = job$name,
                title = job$title,
                description = job$description %||% job$title,
                version = as.character(job$version %||% "0.1.0"),
                script = job$script,
                inputs = lapply(job$inputs, function(e)
                    list(name = e$name, format = e$format,
                         label = e$label %||% e$name,
                         required = !isFALSE(e$required))),
                outputs = lapply(job$outputs, function(e)
                    list(name = e$name, format = e$format,
                         label = e$label %||% e$name)),
                options = lapply(job$options, function(o) {
                    entry <- list(name = o$name, type = o$type,
                                  label = o$label %||% o$name,
                                  required = isTRUE(o$required))
                    if (!is.null(o$default)) entry$default <- o$default
                    if (!is.null(o$choices)) entry$choices <- o$choices
                    entry
                }),
                resources = job$resources,
                depends = as.character(job$depends %||% character()),
                container = job$container %||% .defaultContainer(),
                command = jobCommand(job),
                cli_command = jobCommand(job, style = "cli")
            )
        })
    )
    ## NULL scalars serialize as '{}'; drop them instead.
    manifest <- manifest[!vapply(manifest, is.null, NA)]
    class(manifest) <- c("BiocJobManifest", "list")
    if (!is.null(file)) {
        json <- jsonlite::toJSON(unclass(manifest), auto_unbox = TRUE,
                                 pretty = TRUE)
        writeLines(json, file)
    }
    manifest
}
