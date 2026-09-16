# BiocJobs 0.99.0

* Initial Bioconductor submission.
* Declarative job specifications: a YAML file plus an R script under
  `inst/biocjobs/` describe a package's non-interactive, dispatchable units
  of work (inputs, outputs, typed options, resources, dependencies,
  citations and tests).
* Runtime contract via `jobParams()`: parses `--name value` command-line
  arguments against the specification, applying type coercion, numeric
  bounds, choice validation, defaults and required-parameter checks.
* Local execution with `runJob()` and the self-locating `execJob()` entry
  point used by every generated artifact.
* Generators for GA4GH Task Execution Service (TES) v1.1 tasks
  (`tesTask()`), Galaxy tool wrappers (`galaxyTool()`), Nextflow DSL2
  modules (`nextflowModule()`), WDL 1.0 tasks (`wdlTask()`) and HTCondor
  submit files (`htcondorSubmit()`), plus a per-package job manifest
  (`jobManifest()`) for registry aggregation.
* `jobSkeleton()` scaffolds a new job declaration from a template.
* Command-line interface (`biocjobsCLI()`) exposing discovery, validation,
  local runs and every generator for use in automation.
* Reusable GitHub Actions workflow (`biocjobs-package.yml`) that a package
  fork can call to build its container, generate every wrapper inside it,
  publish them as build artifacts, and lint and test the generated Galaxy
  tool with planemo. A caller template ships in `inst/templates/`.
* `--image` on every generator command, so a CI run can pin generated
  artifacts to the image it just built.
* Optional interoperation with the BiocExecute framework: jobs declared for
  BiocJobs compile directly into command-line subcommands.
