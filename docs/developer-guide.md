# BiocJobs developer guide: making your package dispatchable

This guide takes a package maintainer from an empty `inst/biocjobs/` to
validated wrappers for Galaxy, GA4GH TES, Nextflow, WDL, HTCondor and
Kubernetes. Examples use the `jobSkeleton()` template and the DESeq2 job in
[`examples/DESeq2/`](../examples/DESeq2/).

## Contents

1. [Concepts](#1-concepts)
2. [Is my package a good candidate?](#2-is-my-package-a-good-candidate)
3. [Scaffold](#3-scaffold)
4. [Write the specification](#4-write-the-specification)
5. [Write the script](#5-write-the-script)
6. [Run it locally](#6-run-it-locally)
7. [Validate](#7-validate)
8. [Declare wrapper tests](#8-declare-wrapper-tests)
9. [Generate the wrappers](#9-generate-the-wrappers)
10. [Command-line front ends](#10-command-line-front-ends)
11. [Continuous integration](#11-continuous-integration)
12. [Release checklist](#12-release-checklist)
13. [Containers](#13-containers)
14. [Troubleshooting](#14-troubleshooting)
15. [FAQ](#15-faq)

---

## 1. Concepts

A **job** is one complete, non-interactive unit of analysis your package
can perform: files in, files out, parameters known up front, no human in
the loop.

Each job consists of exactly two files in your package source tree:

```
mypackage/
└── inst/
    └── biocjobs/
        ├── my-analysis.yaml        <- the SPECIFICATION (interface)
        └── scripts/
            └── my-analysis.R       <- the SCRIPT (implementation)
```

The **specification** declares the job's interface: input files and their
formats, output files and their formats, typed configuration options,
resource needs, runtime dependencies, citations, and test cases. BiocJobs
reads it without evaluating R code, so jobs can be listed and validated
from a package tarball.

The **script** is plain R. Its first line hands control of the interface
to the specification:

```r
params <- BiocJobs::jobParams("mypackage", "my-analysis")
```

`jobParams()` parses the command line *against the declaration* (type
coercion, defaults, choice validation, required checks, output directory
creation) and returns a named list. The rest of the script is analysis
code reading `params$<name>`.

The **runtime contract** ties everything together: every input, output,
and option is passed as a `--name value` command-line pair, and every
execution environment launches the same self-locating command:

```
Rscript -e 'BiocJobs::execJob("mypackage", "my-analysis")' --name value ...
```

From the declaration, BiocJobs **generates**:

| Target | Artifact | Consumed by |
|---|---|---|
| Galaxy | tool wrapper XML + staged `test-data/` | Galaxy servers, `planemo test` |
| GA4GH TES | task template JSON | Funnel, TESK, cloud TES endpoints |
| Nextflow | DSL2 module (`process` with `tuple`/`val` inputs, `emit:` outputs, stub) | Nextflow / nf-core pipelines |
| WDL | task (WDL 1.0, `parameter_meta`, runtime) | WDL 1.0 engines (Cromwell, miniwdl) |
| HTCondor | submit description `.sub` + executable `.sh` | `condor_submit`, CHTC via submitr |
| Kubernetes | `batch/v1` Job (YAML) | `kubectl create`, any Kubernetes cluster |
| Manifest | JSON summary of all jobs | registry aggregation, build infra |

## 2. Is my package a good candidate?

Declare a job when the analysis is **batch-shaped**:

- inputs are files (or can reasonably be serialized to files),
- outputs are files,
- every decision a user makes can be expressed as a typed option up front,
- the code path runs unattended from start to finish.

Good fits: differential expression, normalization, peak calling, denoising,
quantification import, batch correction, deconvolution, annotation.

Poor fits: interactive visualization, iterative model tuning with a human
in the loop, browsers, anything requiring a live R session mid-analysis.
Packages like that do not add `inst/biocjobs/`.

One package can declare **several** jobs (e.g. one per major workflow), and
a job does not need to expose everything a function can do: expose the
parameters that matter for batch use, hard-code sensible choices for the
rest, and keep the full flexibility in your R API.

## 3. Scaffold

With BiocJobs installed, from your package source directory:

```r
BiocJobs::jobSkeleton("my-analysis")
```

```
created inst/biocjobs/my-analysis.yaml
created inst/biocjobs/scripts/my-analysis.R
next: edit both files, then validate with
  Rscript -e 'BiocJobs::biocjobsCLI()' validate .
```

The YAML is a valid specification with comments on the common fields, and
the script shows the `jobParams()` contract. Existing files are kept unless
`overwrite = TRUE`.

## 4. Write the specification

The complete field reference. Fields marked *(required)* make
`validateJob()` fail when absent; everything else has a sensible default
or is optional. A job must also declare at least one output.

### Top level

| Field | Meaning |
|---|---|
| `biocjobs` *(required)* | Spec format version. Currently `"1.0"`. |
| `name` *(required)* | Job identifier, `[a-z0-9][a-z0-9._-]*`. Appears in artifact names, CLI subcommands, tags. Prefer dashes (`deseq2-differential-expression`); see the CLI naming note below. |
| `package` *(required)* | Your package name, exactly as in `DESCRIPTION`. |
| `title` *(required)* | One line, human-readable. Becomes the Galaxy tool name and CLI title. |
| `tagline` | Very short description for tool listings (Galaxy `<description>`). |
| `description` | A paragraph. Used in the Galaxy help, the TES task, the WDL `meta` block and the manifest. |
| `version` | Job version (semver string). Drives wrapper versioning; bump it whenever the interface or the script's behavior changes. |
| `license` | License of the generated Galaxy tool (SPDX identifier, default `MIT`). |
| `script` *(required)* | Script path relative to `inst/biocjobs/`. |
| `depends` | R packages the *script* needs beyond your package and its hard dependencies, typically `Suggests` used at runtime (e.g. `[apeglm, ashr]` for DESeq2's shrinkage options). Drives TES bootstrap installs. |
| `container` | Override the default container image for this job. |

**CLI naming note:** a job name becomes a CLI subcommand by mapping `-` to
`_` internally (and back for display), so `my-analysis` is fine, but names
where that mapping produces an invalid R name (e.g. a reserved word like
`if`, or `2pass-align` after mapping) cannot be exposed by the CLI layer.
`validateJob()` emits a note when that happens.

### `inputs`: files the job consumes

```yaml
inputs:
  - name: counts          # flag: --counts <path>. ^[a-z][a-z0-9_]*$
    format: tsv           # from BiocJobs::jobFormats(); drives Galaxy
                          # datatypes and container file extensions
    label: Raw count matrix          # short; UI form labels
    help: >                          # long; UI help, WDL parameter_meta
      Tab-separated matrix of raw integer counts, first column gene ids.
    # required: false     # inputs are required unless you say otherwise
```

Run `BiocJobs::jobFormats()` for the format vocabulary (`tsv`, `csv`,
`rds`, `fasta`, `fastq`, `bam`, `vcf`, `pdf`, ...). Unknown formats are
allowed (they pass through verbatim to generators), but validation flags
them as notes so typos get caught.

### `outputs`: files the job must produce

```yaml
outputs:
  - name: results
    format: tsv
    label: Differential expression results
    help: Per-gene table ordered by adjusted p-value.
```

Every declared output **must** be written by the script, to the path in
`params$<name>`. The local runner warns when a declared output was not
produced; engines treat it as job failure.

### `options`: typed configuration

```yaml
options:
  - name: shrinkage
    type: choice                 # boolean | choice | string | integer | float
    choices: [apeglm, ashr, normal, none]
    default: apeglm
    label: Log2 fold change shrinkage
    help: apeglm is the recommended default.

  - name: alpha
    type: float
    default: 0.1
    min: 0                       # bounds (integer/float): jobParams()
    max: 1                       # enforces them at run time; Galaxy/WDL show them
    label: FDR threshold

  - name: contrast_factor
    type: string
    required: true               # no default -> user must supply
    label: Factor to test

  - name: design
    type: string
    default: "~ condition"
    allow_chars: ["~"]           # extend Galaxy's text sanitizer; see below
    label: Design formula

  - name: prefilter
    type: boolean
    default: true
    label: Pre-filter low-count genes
```

Rules:

- Every option needs either a `default` or `required: true`.
- Inputs, outputs, and options share **one** flag namespace; duplicate
  names across sections are validation errors.
- `allow_chars` matters for string options holding R formulas: Galaxy's
  default text sanitizer strips characters like `~`, which would silently
  corrupt `~ condition` into `condition`. Declaring
  `allow_chars: ["~"]` makes the generated wrapper extend the sanitizer.
  A single quote is not allowed: the Galaxy command passes string values
  inside single quotes.
- Booleans arrive in your script as R logicals; integers as integers;
  floats as doubles; choice values are validated against `choices` before
  your script sees them.

### `resources`: scheduling hints

```yaml
resources:
  cpus: 1
  memory_gb: 4
  disk_gb: 10
```

These map to TES `resources`, Nextflow directives, WDL `runtime`, HTCondor
`request_*` and Kubernetes resource requests. Estimate for a typical dataset; engines can override.

### `citations`

```yaml
citations:
  - doi: 10.1186/s13059-014-0550-8
```

Rendered as Galaxy `<citations>`. Cite your method
paper and the papers behind optional methods your job exposes.

### `tests`: see [Declare wrapper tests](#8-declare-wrapper-tests).

## 5. Write the script

The script template from `jobSkeleton()` shows the contract:

```r
params <- BiocJobs::jobParams("mypackage", "my-analysis")

data <- read.delim(params$input1)
result <- ...                                   # real work
write.table(result, params$output1, sep = "\t",
            quote = FALSE, row.names = FALSE)
```

Rules for job scripts:

1. **First line is `jobParams()`.** After it returns, every value is typed,
   validated, and defaulted. Do not read `commandArgs()` yourself; do not
   add your own defaults downstream (they would drift from the spec that
   generated the UI the user saw).
2. **Fail loudly, early, and specifically.** `stop()` with a message that
   names the offending input and says how to fix it. Non-zero exit is how
   every engine detects failure (`detect_errors="exit_code"` in Galaxy,
   executor exit codes in TES, task failure in Nextflow/WDL).
3. **Never prompt, never open interactive devices**, never `browser()`,
   never assume a display. `pdf(file)` is fine; `plot()` to a default
   device is not.
4. **Write every declared output**, exactly to `params$<name>`.
5. **Log to stderr** with `message()`; engines capture it as the job log.
   A `sessionInfo()` at the end records the provenance of every run.
6. **Validate scientific preconditions defensively.** Batch users can't
   see your data structures. The DESeq2 example script is the reference
   here: it checks, with named errors, for: non-numeric counts, NA cells,
   duplicate gene identifiers, samples missing from the annotation, factor
   levels that DESeq2 would silently rename (non-syntactic names), and
   contrast levels that don't exist. Read it before writing yours:
   [`deseq2-differential-expression.R`](../examples/DESeq2/inst/biocjobs/scripts/deseq2-differential-expression.R).
7. **Read TSV/CSV robustly**: `read.delim(..., quote = "", comment.char = "")`
   unless the format uses quoting; otherwise a stray `"` in an identifier
   can swallow rows.
8. Package your script's *extra* runtime dependencies in `depends:`
   (anything in your package's `Suggests` that the script loads).

## 6. Run it locally

The local runner executes the job in a fresh `Rscript` process from your
source checkout, with no installation needed and the same contract as
production:

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' run . my-analysis \
    --input1 test-data/input1.tsv \
    --method fast
```

```
workdir: /tmp/biocjob_1a2b3c
output output1: /tmp/biocjob_1a2b3c/output1.tsv
```

Or from R: `runJob(readJob("inst/biocjobs/my-analysis.yaml"),
params = list(input1 = "..."))`.

Test the failure paths too: a missing required flag, a wrong choice value,
a malformed input file. Each should produce one clear error line, because
that line is what a Galaxy or Nextflow user will see in their job log.

## 7. Validate

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' validate .
```

```
all job specifications valid
```

`validate` exits non-zero on errors, so wire it into your CI next to
`R CMD check`. **Errors** (missing fields, bad option types, defaults not
among choices, duplicate flag names, missing script, no outputs) make the
job unusable. **Notes** (no label, unknown format, CLI-incompatible name,
missing test files) are advisory but worth fixing before release.

## 8. Declare wrapper tests

```yaml
tests:
  - inputs:
      counts: test-data/counts.tsv        # relative to your package root
      coldata: test-data/coldata.tsv
    options:
      contrast_factor: condition
      contrast_numerator: treated
      contrast_denominator: control
    outputs:
      results:
        file: test-data/results.tsv       # expected output
        compare: sim_size                 # size comparison with tolerance
        delta: 3000
      ma_plot: {}                         # just assert it exists/non-empty
```

These become `<tests>` in the Galaxy wrapper, and the referenced files are
staged into `test-data/` next to the generated XML, the layout
`planemo test` expects. Keep test data tiny (the DESeq2 example simulates
600 genes × 6 samples with a fixed seed; the generator script is committed
next to the data). Generate expected outputs by running the job once
locally and copying the results; the test then pins today's behavior.

## 9. Generate the wrappers

All generators run from the shell (for CI) or from R. Each regenerates a
deterministic artifact; commit them or regenerate at release time, but
never hand-edit them.

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' galaxy   . my-analysis --out wrappers/my_analysis.xml
Rscript -e 'BiocJobs::biocjobsCLI()' tes      . my-analysis --out wrappers/my-analysis.tes.json
Rscript -e 'BiocJobs::biocjobsCLI()' nextflow . my-analysis --out wrappers/my_analysis.nf
Rscript -e 'BiocJobs::biocjobsCLI()' wdl      . my-analysis --out wrappers/my_analysis.wdl
Rscript -e 'BiocJobs::biocjobsCLI()' htcondor . my-analysis --out wrappers/my-analysis.sub
Rscript -e 'BiocJobs::biocjobsCLI()' kubernetes . my-analysis --out wrappers/my-analysis.k8s.yaml
Rscript -e 'BiocJobs::biocjobsCLI()' manifest . --out wrappers/manifest.json
```

### Galaxy

Complete tool XML: typed params, sanitizers and validators, outputs with
datatypes and labels, tests, citations, a `bioconductor` xref, and a
`<container type="docker">` requirement naming the job's image. Tool
version follows IUC convention with your package version leading
(`1.52.0+biocjobs1.0.0`), so regeneration after a Bioconductor release
yields a new tool version automatically. Test data is staged beside the
XML. Check it with `planemo lint` / `planemo test`; the DESeq2 artifact
validates against Galaxy's official XSD.

### GA4GH TES

A TES v1.1 task template, schema-valid for `POST /tasks`. Inputs/outputs
are staged at fixed container paths; unknown-at-generation-time values are
`{{...}}` placeholders and the task is tagged `biocjobs.template: "true"`.
Submission tooling fills the placeholders; if an unfilled placeholder ever
reaches a run, `jobParams()` rejects it by name. On the generic
Bioconductor image, a bootstrap executor installs your package, BiocJobs,
and `depends` at task start; with a purpose-built `container:` the
bootstrap disappears.

### Nextflow

A DSL2 module: one `process`, options as `val` (annotated with
types/defaults from the spec), outputs under stable `emit:` names, resource
directives, and a `stub:` block so pipelines can be smoke-tested with
`-stub-run` before touching real data.

By default the module follows the nf-core convention: all of the job's file
inputs travel together in one `tuple val(meta), path(...)` input led by a
`meta` map, each output is emitted as `tuple val(meta), path(...)` so the
map flows on to the next process, and the process `tag` is `${meta.id}`.
Use it like any module:

```nextflow
include { MY_ANALYSIS } from './modules/my_analysis.nf'

workflow {
    ch = channel.of([ [id: 'sample1'], file(params.input1) ])
    MY_ANALYSIS(ch, 'fast', 0.05)          // options, in declared order
    MY_ANALYSIS.out.output1.view()         // [ [id:sample1], output1.tsv ]
}
```

Pipelines that do not use meta maps can opt out with
`nextflowModule(job, meta = FALSE)`, which emits plain `path` inputs and
tags with the first input file's name instead.

Two things to know about the generated module: process inputs are
**positional** (Nextflow has no named process-input syntax), so the calling
workflow must pass the file inputs and then every option, in the order they
appear in the specification. Reordering options in a future spec version
changes the call signature, so bump the job `version:` when you do.  Each
option is a required `val` with no in-module default (its spec default is
shown in a comment); supply all of them, typically wired to `params.*` in
your pipeline config.

### WDL

A WDL 1.0 task: `File` inputs, typed inputs with defaults (absent default
= required, enforced by WDL itself), outputs collected from the working
directory, `runtime` from resources, and `parameter_meta` carrying labels,
help, choices, and bounds. The DESeq2 task passes `miniwdl check`. Import
it from a workflow:

```wdl
import "my_analysis.wdl" as jobs

workflow analyze {
    input { File input_file }
    call jobs.my_analysis { input: input1 = input_file, method = "fast" }
}
```

### HTCondor

Two files: an HTCondor submit description (`<job>.sub`) and the executable
shell script it runs (`<job>.sh`, written beside it and marked executable).
Declared inputs become `transfer_input_files`, outputs become
`transfer_output_files`, `resources` become
`request_cpus`/`request_memory`/`request_disk`, and the job's container
becomes a `container_image` under the container universe, with a
`docker://` transport prefix so HTCondor resolves it from the registry
rather than treating it as a path to a local image file.

HTCondor has no typed parameters, so the script is a concrete command: each
option gets its declared default, and a required option without one becomes
a `{{options.<name>}}` placeholder to fill before submitting. `jobParams()`
rejects a placeholder that reaches a running job.

Transferred inputs land in the
job's scratch directory **by basename**, so the generated script refers to
every file by basename. Point `transfer_input_files` at wherever your files
live; their names on the submit side do not have to match.

```bash
condor_submit my-analysis.sub
```

The emitted pair is what the
[submitr](https://cran.r-project.org/package=submitr) package stages and
submits to an HTC submit node such as CHTC, so the two compose directly:

```r
cfg <- submitr::htc_config()
submitr::htc_upload(
    files = c("my-analysis.sub", "my-analysis.sh", "input1.tsv"),
    config = cfg)
submitr::htc_submit(submit_file = "my-analysis.sub", config = cfg)
submitr::htc_status(cluster_id = ..., config = cfg, watch = TRUE)
submitr::htc_download(files = "*.tsv", config = cfg, local_path = "results/")
```

### Kubernetes

A `batch/v1` Job whose pod runs once (`backoffLimit: 0`,
`restartPolicy: Never`). An init container per input downloads it with
`curl` into the volume `work`, mounted at `/biocjob`; the `job` container
runs the canonical command from there with inputs under `/biocjob/inputs`
and outputs under `/biocjob/outputs`. Both containers use the image from
`container:` or the `image` argument, which must provide `curl` as well as
R, BiocJobs and your package; there is no default image.

`resources` map to CPU, memory and `ephemeral-storage` requests, a memory
limit equal to the request, and the `emptyDir` size limit. The pod mounts no
service account token and its containers drop all Linux capabilities. It
does not set `runAsNonRoot`, so namespaces enforcing the `restricted` Pod
Security Standard reject it; `baseline` admits it.

Required inputs without a URL and required options without a value are
`{{...}}` placeholders, as in the TES task, and the Job is annotated
`biocjobs.template: "true"` while any remain. An optional input without a
URL is left out. From R, supply them when generating:

```r
job <- BiocJobs::readJob("inst/biocjobs/my-analysis.yaml")
k8s <- BiocJobs::kubernetesJob(job,
    inputs = c(input1 = "https://example.org/input1.tsv"),
    options = list(method = "fast"))
BiocJobs::writeKubernetesJob(k8s, "my-analysis.k8s.yaml")
```

The Job is named through `metadata.generateName`, so every submission gets
a new name. Submit it with `kubectl create`; `kubectl apply` requires a
fixed name:

```bash
kubectl create -f my-analysis.k8s.yaml
```

The `work` volume is an `emptyDir`, lost when the job ends. To keep the
outputs, pass `claim = "<pvc>"` (`--claim` on the command line) to mount a
PersistentVolumeClaim instead.

### Manifest

One JSON document per package listing every job with its typed interface,
resources, container and command. Build infrastructure can collect
manifests from tarballs without running package code.

## 10. Command-line front ends

A command-line front end that parses the arguments itself, for example a
[Rapp](https://cran.r-project.org/package=Rapp) application, hands the
parsed values to `execJob()`:

```r
BiocJobs::execJob("mypackage", "my-analysis",
                  values = list(input1 = "data.tsv", method = "fast"))
```

The script's `jobParams()` call then uses these values instead of the
command line, so required options, choice membership, bounds and file
existence are checked against the specification, with the same error
messages as on every other target. Values of `NULL` or `NA` count as not
supplied.

A front end that exposes each job as a subcommand maps `-` in the job name
to `_` for the R name and back for display; `cliJobName()` returns the
token, and `jobCommand(job, values, style = "cli")` builds the
`<Package> <job> --flag value` command line for such a launcher.

## 11. Continuous integration

The repository ships a GitHub Action, `biocjobs-action`, that builds your
package's container image, generates every wrapper inside it, uploads the
wrappers as a build artifact, and lints and tests the generated Galaxy tool
with planemo.

Add `.github/workflows/biocjobs.yml` to your package:

```yaml
name: BiocJobs
on:
  push:
    branches: [devel, RELEASE_*]
  pull_request:
jobs:
  biocjobs:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v7
      - uses: almahmoud/BiocJobs/biocjobs-action@main
```

The action builds the image itself: your package, every dependency in its
DESCRIPTION and BiocJobs on `ghcr.io/bioconductor/bioconductor` at the
branch's Bioconductor version. Pass `dockerfile:` to use your own recipe.
A job that declares `container:` runs in that image and nothing is built
for it, unless the declared image is the one the action builds.
[`examples/DESeq2/.github`](../examples/DESeq2/.github) has the workflow;
the action's [README](../biocjobs-action/README.md) lists every input.

- Wrappers are uploaded as a build artifact; nothing is committed to your
  repository.
- Generation runs inside the built image, so the runner installs no R.
  Each wrapper names that image, by digest once it has been pushed.
- Pull requests cannot push the image, but the Galaxy test still runs
  against the image built on the runner.
- A GHCR package created by Actions is private until you make it public in
  the package settings.

For the Galaxy test to run, the job's `tests:` block must reference files
that exist relative to the package root; the generator stages them next to
the tool XML. A tool with no tests is linted only, and missing test files
fail the run. The run summary lists each tool's result, and planemo's HTML
report is attached to the run.

## 12. Release checklist

- [ ] `Rscript -e 'BiocJobs::biocjobsCLI()' validate .` exits 0, ideally in CI
- [ ] Job runs end-to-end locally on the committed test data
- [ ] Failure paths produce single, clear error lines
- [ ] `version:` bumped if the interface or behavior changed
- [ ] Artifacts regenerated (`galaxy`, `tes`, `nextflow`, `wdl`, `htcondor`,
      `kubernetes`, `manifest`)
- [ ] Generated Galaxy XML passes `planemo lint`, WDL passes
      `miniwdl check`, Nextflow module passes `nextflow lint`
- [ ] `DESCRIPTION` has `Suggests: BiocJobs`
- [ ] Test data is small, deterministic (fixed seed), and its generator
      script is committed
- [ ] If you commit generated artifacts, regenerate them in the same
      change: they record the BiocJobs version that produced them

## 13. Containers

A job needs three things at runtime: R, your package (plus `depends`), and
BiocJobs. Generated artifacts default to
`bioconductor/bioconductor_docker:<current release>`; on that image the TES
task first installs what is missing. The Kubernetes Job has no default and
needs `container:` or `image`. For production, build an image with
everything installed and set `container:`:

```dockerfile
FROM bioconductor/bioconductor_docker:RELEASE_3_23
RUN Rscript -e 'BiocManager::install(c("BiocJobs", "mypackage", "apeglm"), \
                update = FALSE, ask = FALSE)'
```

The container is the entry way for every target, Galaxy included: the
generated tool's only requirement is a `<container type="docker">` naming
the same image the TES task, Nextflow module, WDL task, HTCondor submit
file and Kubernetes Job use. Declaring `container:` in the spec therefore
controls where a job runs on every target.

Galaxy tools declare only the container, not Bioconda package requirements.

## 14. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `package 'X' is not installed or ships no biocjobs/ directory` | Your package isn't installed and `BIOCJOBS_SPEC` isn't set. `runJob()` and the CLI `run` command set it for you; when invoking a script directly during development, `export BIOCJOBS_SPEC=inst/biocjobs/<job>.yaml`. |
| `unknown parameter(s): --foo` | Flag not declared in the spec. The error lists every declared flag. |
| `option --x: 'y' is not one of: ...` | Value outside `choices`. Fix the caller, or extend `choices`. |
| `missing required input --counts` | Required input not supplied; inputs are required unless `required: false`. |
| `unfilled template placeholder(s): --contrast_factor {{options.contrast_factor}}` | A generated TES, HTCondor or Kubernetes template ran with unfilled placeholders. |
| `declared output(s) not produced: results` | Script exited 0 but didn't write an output. Write every declared output or fail loudly. |
| `invalid job specification ... needs either a 'default' or 'required: true'` | Every option must be resolvable: give it a default or mark it required. |
| Galaxy strips `~` from my formula option | Declare `allow_chars: ["~"]` on that option and regenerate. |
| `'name' cannot be exposed as a CLI subcommand` (note) | The name maps to an invalid R identifier (e.g. a reserved word). Rename the job if you want a CLI. |
| Generated Galaxy test can't find files | Test file paths are relative to the package root and must exist at generation time; the generator stages them next to the XML. |

## 15. FAQ

**My package is interactive. Should I force a job anyway?** No. Jobs are
for batch-shaped work. If some core computation *inside* the interactive
flow is batch-shaped (fit a model, score a matrix), consider exposing just
that.

**Can one package declare several jobs?** Yes: one YAML and script pair per
job. Names share a namespace within the package.

**Multiple files per input? Collections?** Not in spec 1.0. Workarounds:
accept an archive (`format: tar`, `tar.gz` or `zip`, all in
`jobFormats()`, and unpack it in the script) or a directory-listing TSV. Multi-file inputs are on the roadmap.

**Where do defaults live, spec or script?** Spec, always. The script must
not re-default anything; the generated UIs show the spec's defaults, and a
script that overrides them silently misleads users.

**What R version / dependencies does the spec assume?** Whatever your
package declares. Generators pin the container to a Bioconductor release;
the spec's `depends` only adds runtime-loaded extras.

**Do I commit generated artifacts?** Either commit them (reviewable diffs,
consumable directly from your repo) or regenerate in CI at release time.
Never edit them by hand.

**How does this relate to writing a Galaxy wrapper / nf-core module by
hand?** Hand-written wrappers can be richer (conditionals, collections,
`ext.args`). Generated ones are consistent, always in sync with the
package, and exist for the long tail of packages nobody wraps by hand. If
a community later hand-tunes a wrapper, the generated one still serves as
the tested baseline.

---

*The complete worked example (spec, script, test data and the generated
artifacts) lives in [`examples/DESeq2/`](../examples/DESeq2/).
The [README](../README.md) gives an overview, and
`vignette("BiocJobs")` is a shorter runnable tour of the same ground.*

*This guide is for maintainers **using** BiocJobs in their own package. To
contribute to BiocJobs itself (a new generator, a spec change, a bug fix),
see [CONTRIBUTING.md](../CONTRIBUTING.md).*
