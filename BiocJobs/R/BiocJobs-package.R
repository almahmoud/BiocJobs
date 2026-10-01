#' BiocJobs: declare and dispatch batch jobs from Bioconductor packages
#'
#' BiocJobs lets a package declare, inside itself, the non-interactive units
#' of work ("jobs") it can perform, and generates from each declaration
#' everything workflow infrastructure needs to dispatch it: GA4GH Task
#' Execution Service (TES) tasks, Galaxy tool wrappers, Nextflow DSL2
#' modules, WDL tasks, HTCondor submit files, Kubernetes Jobs and a
#' machine-readable manifest.
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
#'     [tesTask()], [writeTesTask()], [galaxyTool()],
#'     [writeGalaxyTool()], [nextflowModule()],
#'     [wdlTask()], [htcondorSubmit()], [kubernetesJob()],
#'     [writeKubernetesJob()], [jobManifest()].
#'   \item Command line: [biocjobsCLI()].
#' }
#'
#' @keywords internal
"_PACKAGE"
