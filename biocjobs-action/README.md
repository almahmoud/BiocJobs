# BiocJobs action

Builds a package's container image, generates its BiocJobs wrappers inside
that image, and lints and tests the Galaxy tool with planemo. Wrappers are
uploaded as a build artifact; nothing generated is committed.

## Usage

```yaml
jobs:
  biocjobs:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write      # push the image to GHCR
    steps:
      - uses: actions/checkout@v7
      - uses: almahmoud/BiocJobs/biocjobs-action@main
```

Without a `dockerfile` input the action builds its own image: the package,
every dependency in its DESCRIPTION and BiocJobs, on
`ghcr.io/bioconductor/bioconductor` at the branch's Bioconductor version.
Supply `dockerfile` for anything else; it must produce an image with R, the
package and BiocJobs installed.

A job whose YAML declares `container:` runs in that image instead: the
action builds nothing for it and keeps the declared reference in its
wrappers. The image must have R, the package and BiocJobs installed and be
pullable by the runner (log in before the action for a private image). A
declared container naming the image this action builds (`image-name`, any
tag) is still built here. See
[`examples/DESeq2/.github`](../examples/DESeq2/.github) for a complete
example.

## What it does

1. Builds the image, unless every job declares its container, and on
   pushes publishes it to the registry.
2. Runs `BiocJobs::biocjobsCLI()` inside the image: `validate` once, then
   `galaxy`, `tes`, `nextflow`, `wdl` and `htcondor` for every declared
   job, then `manifest` for the package. Wrappers name the built image by
   digest when it was pushed.
3. Uploads the wrappers as an artifact.
4. Runs `planemo lint` on each Galaxy tool, then one `planemo test --docker`
   over the tools that declare tests. The images are already on the runner,
   so tests run for pull requests too.
5. Uploads planemo's HTML report unzipped, so it opens in the browser from
   the run page. The run summary lists each tool's lint and test result.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `package-dir` | `.` | package source directory |
| `dockerfile` | the action's | image recipe |
| `docker-context` | `package-dir` | build context |
| `base-image` | `ghcr.io/bioconductor/bioconductor:<branch>` | base for the action's Dockerfile |
| `reclaim-disk` | `true` | free runner disk before building |
| `image-name` | `ghcr.io/<repository>` | image name, lowercased |
| `image-tag` | branch or tag name | image tag |
| `push-image` | `true` | push after building; skipped for pull requests |
| `registry` | `ghcr.io` | registry to log in to |
| `registry-username` | `github.actor` | registry user |
| `registry-password` | `github.token` | registry password or token |
| `job-names` | all | space-separated jobs to generate |
| `artifact-name` | `biocjobs-wrappers` | uploaded artifact |
| `report-name` | `planemo-report.html` | planemo report artifact, unique within the run |
| `run-planemo` | `true` | lint and test the Galaxy tools |
| `planemo-version` | `0.75.47` | planemo release |
| `galaxy-branch` | `release_26.1` | Galaxy branch planemo tests against |
| `python-version` | `3.11` | Python for planemo and Galaxy |

## Outputs

| Output | Meaning |
|---|---|
| `image` | image built here, as written into the wrappers; empty when every job declares its container |
| `wrappers` | directory holding the generated wrappers |

## Notes

- A GHCR package created by Actions is private until made public in the
  package settings.
- Galaxy tests come from the `tests:` block in the job specification; the
  generator stages the files it names next to the tool XML. A tool without
  tests is linted only; one whose test files are missing from the package
  fails, naming the files.
- The action runs in the caller's job, so the caller checks out the
  repository and grants `packages: write` when the image should be pushed.

## Testing the scripts locally

`scripts/generate.sh` uses the host `Rscript` when `IMAGE` is unset:

```bash
PACKAGE_DIR=path/to/pkg OUT_DIR=/tmp/wrappers \
    biocjobs-action/scripts/generate.sh
```
