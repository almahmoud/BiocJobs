# BiocJobs

BiocJobs lets a Bioconductor package declare its non-interactive analyses as
jobs, and generates from each declaration what workflow systems need to run
it: Galaxy tools, GA4GH TES tasks, Nextflow modules, WDL tasks, HTCondor
submit files, Kubernetes Jobs and a package job manifest.

A job is two files in the package source:

```
mypackage/inst/biocjobs/
├── my-analysis.yaml      # inputs, outputs, typed options, resources, tests
└── scripts/
    └── my-analysis.R     # the analysis
```

BiocJobs reads the YAML without loading or running package code. The script
starts with

```r
params <- BiocJobs::jobParams("mypackage", "my-analysis")
```

which parses `--name value` arguments against the YAML and returns typed,
validated values with defaults applied. Every generated artifact runs the
job with the same command, and `execJob()` finds the script in the
installed package:

```
Rscript -e 'BiocJobs::execJob("mypackage", "my-analysis")' --name value ...
```

## Installation

BiocJobs requires R >= 4.6.0.

```r
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install("almahmoud/BiocJobs", subdir = "BiocJobs")
```

## Usage

In a package source directory, scaffold a job, edit the two files, then
validate, run and generate:

```r
BiocJobs::jobSkeleton("my-analysis")
```

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' validate .
Rscript -e 'BiocJobs::biocjobsCLI()' run . my-analysis --input1 data.tsv
Rscript -e 'BiocJobs::biocjobsCLI()' galaxy . my-analysis --out my_analysis.xml
```

`validate` exits with status 1 when a specification has errors.
`Rscript -e 'BiocJobs::biocjobsCLI()' help` lists every command. From R, use
`findJobs()`, `validateJob()`, `runJob()` and the generators below.

## Targets

| Target | R | CLI | Output |
|---|---|---|---|
| Galaxy | `galaxyTool()`, `writeGalaxyTool()` | `galaxy` | tool XML, with the files its tests use in `test-data/` |
| GA4GH TES 1.1 | `tesTask()`, `writeTesTask()` | `tes` | task JSON |
| Nextflow | `nextflowModule()` | `nextflow` | DSL2 module with one process and a `stub:` block |
| WDL 1.0 | `wdlTask()` | `wdl` | task |
| HTCondor | `htcondorSubmit()` | `htcondor` | submit file and the script it runs |
| Kubernetes | `kubernetesJob()`, `writeKubernetesJob()` | `kubernetes` | `batch/v1` Job |
| Manifest | `jobManifest()` | `manifest` | JSON describing every job of a package |

Artifacts run in the image named by the job's `container:` field or by
`--image`. Without either they use `bioconductor/bioconductor_docker` for the
current Bioconductor release, and the TES task first installs the package,
BiocJobs and the job's `depends`; the Kubernetes generator requires an image.
In TES tasks, HTCondor submissions and Kubernetes Jobs, values not known at
generation time, such as input URLs and required options, are written as
`{{...}}` placeholders. `jobParams()` rejects a placeholder that reaches a
running job.

## Documentation

- `vignette("BiocJobs")`: a runnable walkthrough with the `toy` package
  shipped in BiocJobs.
- [Developer guide](docs/developer-guide.md): the specification, each
  target, continuous integration and troubleshooting.
- [`examples/DESeq2`](examples/DESeq2/): a complete job and its generated
  artifacts.
- [CONTRIBUTING.md](CONTRIBUTING.md): development setup and adding a target.

## Repository

| Path | Contents |
|---|---|
| [`BiocJobs/`](BiocJobs/) | the R package |
| [`biocjobs-action/`](biocjobs-action/) | GitHub Action that builds a package image, generates its wrappers and tests the Galaxy tools with planemo |
| [`biocjobs-test-galaxy/`](biocjobs-test-galaxy/) | wrappers deployed to the test Galaxy at https://testgalaxy.bioconductor.org |
| [`docs/`](docs/) | developer guide |
| [`examples/`](examples/) | DESeq2 and VariantAnnotation jobs |

## License

Artistic-2.0
