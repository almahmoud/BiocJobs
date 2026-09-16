# Contributing to BiocJobs

Thanks for helping. BiocJobs is a small package with a strict contract: a
job specification is the single source of truth, and everything else —
the runtime `--name value` command line, the Galaxy/TES/Nextflow/WDL
artifacts, the manifest — is derived from it. Contributions are easiest to
review when they keep that direction of flow.

## Setup

You need R (>= 4.6.0) and the package dependencies:

```r
install.packages(c("yaml", "jsonlite", "xml2"))            # Imports
install.packages(c("testthat", "knitr", "rmarkdown"))      # Suggests
BiocManager::install("BiocStyle")                          # vignette
```

Then install the package from a source checkout of the repository:

```bash
R CMD INSTALL BiocJobs
```

Optional, only needed to check generated artifacts against the tools that
consume them: `xmllint` (libxml2), `miniwdl` and `nextflow` — CI installs
these three, so you can also just let CI do it — plus `planemo` if you
want to lint or run the Galaxy wrapper the way Galaxy's tool developers
do.

## Running the tests

```r
testthat::test_local("BiocJobs")
```

or the full check the way CI runs it:

```bash
R CMD build BiocJobs && R CMD check BiocJobs_*.tar.gz
Rscript -e 'BiocCheck::BiocCheck("BiocJobs", `new-package` = TRUE)'
```

The suite needs no network and no Bioconductor experiment data. The `toy`
example package shipped at `BiocJobs/inst/examples/toy` is the fixture for
tests that exercise a real job end to end; `examples/DESeq2` is
documentation only.

## Generated artifacts are never hand-edited

Everything under `examples/DESeq2/generated/` (and `exec/`) is generator
output. If an artifact is wrong, fix the generator or the specification and
regenerate — a hand-edit is silently reverted by the next regeneration and
CI will reject it.

Regenerate from the repository root, with BiocJobs installed:

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' validate examples/DESeq2
Rscript -e 'BiocJobs::biocjobsCLI()' tes      examples/DESeq2 deseq2-differential-expression --out examples/DESeq2/generated/deseq2-differential-expression.tes.json
Rscript -e 'BiocJobs::biocjobsCLI()' galaxy   examples/DESeq2 deseq2-differential-expression --out examples/DESeq2/generated/deseq2_differential_expression.xml
Rscript -e 'BiocJobs::biocjobsCLI()' nextflow examples/DESeq2 deseq2-differential-expression --out examples/DESeq2/generated/deseq2_differential_expression.nf
Rscript -e 'BiocJobs::biocjobsCLI()' wdl      examples/DESeq2 deseq2-differential-expression --out examples/DESeq2/generated/deseq2_differential_expression.wdl
Rscript -e 'BiocJobs::biocjobsCLI()' manifest examples/DESeq2 --out examples/DESeq2/generated/manifest.json
```

`exec/DESeq2.R` is regenerated separately with
`BiocExecute::execCompile('examples/DESeq2')`, which needs the BiocExecute
`feat/biocjobs-specs` branch; CI therefore skips that one step. Refresh it
by hand when the job interface changes.

Note that the artifacts embed the BiocJobs version, so bumping `Version:`
in `DESCRIPTION` makes them stale: regenerate in the same commit.

Roxygen documentation is generated too — edit the roxygen comments in
`BiocJobs/R/`, then `roxygen2::roxygenise("BiocJobs")`; never edit
`man/*.Rd` or `NAMESPACE` directly.

## What CI enforces

Three workflows run on every push and pull request to `main`
(`.github/workflows/`):

- **check** — `R CMD check` via `rcmdcheck` with `error_on = "warning"`,
  then ``BiocCheck::BiocCheck(getwd(), `new-package` = TRUE)``, both inside
  `bioconductor/bioconductor_docker:devel`. Warnings are failures.
- **artifacts** — regenerates every artifact of the DESeq2 example and
  fails on `git diff --exit-code` (stale committed output) or on a
  generated file that was never committed; then validates each artifact
  against the schema of the system that consumes it: the Galaxy tool XSD
  (`xmllint --schema`), the GA4GH TES 1.1 `tesTask` schema
  (`.github/scripts/validate-tes-task.py`, which also checks the
  create-task rules), `miniwdl check`, and `nextflow lint`.
- **action** — runs `biocjobs-action` against the toy package: builds the
  image from `.github/docker/Dockerfile.toy`, generates every wrapper
  inside it and lints the Galaxy tool with planemo.

A red **artifacts** run almost always means "you changed a generator or a
spec and did not commit the regenerated files".

## Code style

- 4-space indent, no tabs; lines under 80 columns.
- No `<<-`; no assignment into the global environment, and no `library()`
  or `require()` calls inside package code.
- `snake_case` for local variables, `camelCase` for exported functions,
  a leading `.` for internal helpers (`.wdlType()`, `.nfVar()`).
- Every exported function is roxygen-documented with a runnable
  `@examples` block; internal files start with a short comment explaining
  what the file is for and why it is shaped that way.
- Comments explain intent (especially escaping and cross-language quoting
  rules, which are the subtle part of this package), not mechanics.
- No new hard dependencies without discussion; `Imports:` is deliberately
  four packages.

## Adding a new generator

`R/nextflow.R` and `R/wdl.R` are the two smallest complete generators —
read them first; a CWL or Snakemake target is the same shape. A generator
is a pure function of a `BiocJob` object that returns text and optionally
writes it to `file`; it must not run the job, read the environment, or
touch anything outside the spec.

Touch points for a new target `foo`:

1. `BiocJobs/R/foo.R` — the generator, exported as `fooTask()`/`fooModule()`,
   plus internal helpers for that language's identifier and string
   escaping rules. Emit the canonical command
   (`Rscript -e 'BiocJobs::execJob("pkg", "job")' --flag value`); never
   invent a second calling convention.
2. `NAMESPACE` / `man/` — via roxygen (`roxygen2::roxygenise()`).
3. `BiocJobs/R/cli.R` — add the subcommand to `.CLI_USAGE`, to the allowed-command
   vector in `.cliDispatch()`, and to the generator branch of the
   `switch()`.
4. `tests/testthat/test-wdl-nextflow.R` (or a new `test-foo.R`) — cover
   the happy path plus the escaping edge cases: quotes and backslashes in
   labels, reserved words as option names, a name starting with a digit,
   boolean and choice options, absent defaults.
5. Docs — `README.md`, `docs/developer-guide.md` (Step 7), and the
   `examples/DESeq2` README table; then regenerate the example artifacts
   and commit them.
6. `.github/workflows/artifacts.yaml` — add a generation command and a
   validation step using that ecosystem's own linter, so the new artifact
   is guarded like the others.
7. `biocjobs-action/scripts/generate.sh` — add the target to the list the
   action generates.

## Bugs, and changes to the specification

Open an issue at
<https://github.com/almahmoud/BiocJobs/issues>. For a bug, include the
job YAML (or a minimal version of it), the exact command, and the full
error message; specification bugs are much easier to fix from the YAML
than from a description.

Changes to the specification format itself are the highest-cost changes
here, because every declared job in every package is written against it.
Propose them as an issue before opening a pull request, and say what a
maintainer with an existing spec has to do. The format carries a version:
`.SPEC_VERSION` in `BiocJobs/R/spec.R`, matched against the `biocjobs:` field of
every spec.

- Additive, optional fields: no version bump; document the field, add
  validation for it, and make sure a spec without it behaves as before.
- Anything that would invalidate, or silently change the meaning of, an
  existing spec: bump `.SPEC_VERSION`, and describe the migration in
  `NEWS.md`.

New option types, new `format:` entries in `jobFormats()`, and new
resource fields are all specification changes — they have to be mapped
onto *every* target, so include the generator updates in the same pull
request.

---

## Documentation status

This documentation was drafted with AI assistance and has not yet been fully
reviewed. It may be inaccurate or out of date in places until every claim has
been checked against the implementation. Treat it as provisional while this
notice is present; it will be removed once the review is complete.
