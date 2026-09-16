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

The package's Dockerfile (`.github/docker/Dockerfile` by default) must
produce an image with R, the package and BiocJobs installed. See
[`examples/DESeq2/.github`](../examples/DESeq2/.github) for a complete
example.

## What it does

1. Builds the image and, on pushes, publishes it to the registry.
2. Runs `BiocJobs::biocjobsCLI()` inside the image: `validate`, then
   `galaxy`, `tes`, `nextflow`, `wdl`, `htcondor` and `manifest` for every
   declared job. Wrappers name the image by digest when it was pushed.
3. Runs `planemo lint` on each Galaxy tool, then `planemo test --docker`
   on those with staged test data. The image is already on the runner, so
   tests run for pull requests too.
4. Uploads the wrappers and test reports as an artifact.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `package-dir` | `.` | package source directory |
| `dockerfile` | `.github/docker/Dockerfile` | image recipe |
| `docker-context` | `.` | build context |
| `image-name` | `ghcr.io/<repository>` | image name, lowercased |
| `image-tag` | branch or tag name | image tag |
| `push-image` | `true` | push after building; skipped for pull requests |
| `registry` | `ghcr.io` | registry to log in to |
| `registry-username` | `github.actor` | registry user |
| `registry-password` | `github.token` | registry password or token |
| `job-names` | all | space-separated jobs to generate |
| `artifact-name` | `biocjobs-wrappers` | uploaded artifact |
| `run-planemo` | `true` | lint and test the Galaxy tools |
| `planemo-version` | `0.75.47` | planemo release |
| `galaxy-branch` | `release_26.1` | Galaxy branch planemo tests against |
| `python-version` | `3.11` | Python for planemo and Galaxy |

## Outputs

| Output | Meaning |
|---|---|
| `image` | image reference written into the wrappers |
| `wrappers` | directory holding the generated wrappers |

## Notes

- A GHCR package created by Actions is private until made public in the
  package settings.
- Galaxy tests need a `tests:` block in the job specification whose files
  exist in the package; the generator stages them next to the tool XML.
  A tool without staged test data is linted only.
- The action runs in the caller's job, so the caller checks out the
  repository and grants `packages: write` when the image should be pushed.

## Testing the scripts locally

`scripts/generate.sh` uses the host `Rscript` when `IMAGE` is unset:

```bash
PACKAGE_DIR=path/to/pkg OUT_DIR=/tmp/wrappers biocjobs-action/scripts/generate.sh
```
