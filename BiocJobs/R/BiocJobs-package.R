#' BiocJobs: declare and dispatch batch jobs from Bioconductor packages
#'
#' BiocJobs lets a package declare, inside itself, the non-interactive units
#' of work ("jobs") it can perform, and generates from each declaration
#' everything workflow infrastructure needs to dispatch it: GA4GH Task
#' Execution Service (TES) tasks, Galaxy tool wrappers, Nextflow DSL2
#' modules, WDL tasks, a machine-readable manifest, and -- through the
#' BiocExecute framework -- a command line.
#'
#' A job is two files under `inst/biocjobs/`: a YAML specification declaring
#' inputs, outputs, typed options, resources, dependencies, citations and
#' tests; and an R script whose first line hands the interface to the
#' specification via [jobParams()].
#' See `vignette("BiocJobs")` and the developer guide for a full
#' walkthrough.
#'
#' Key entry points:
#' \itemize{
#'   \item Discovery and validation:
#'     [findJobs()], [readJob()],
#'     [validateJob()],
#'     [jobFormats()],
#'     [jobSkeleton()].
#'   \item Runtime:
#'     [jobParams()], [execJob()],
#'     [runJob()], [jobCommand()].
#'   \item Generators:
#'     [tesTask()], [galaxyTool()],
#'     [nextflowModule()],
#'     [wdlTask()], [jobManifest()].
#'   \item Command line: [biocjobsCLI()].
#' }
#'
#' @keywords internal
"_PACKAGE"
