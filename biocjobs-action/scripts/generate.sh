#!/usr/bin/env bash
# Generate every BiocJobs wrapper for one package.
#
#   PACKAGE_DIR  package source directory (default: .)
#   OUT_DIR      output directory (default: ./wrappers)
#   JOB_NAMES    space-separated job names; empty means all
#   IMAGE        run R inside this image; empty uses the host Rscript
#   PINNED       image reference written into the wrappers via --image
set -euo pipefail

pkg_host=$(cd "${PACKAGE_DIR:-.}" && pwd)
mkdir -p "${OUT_DIR:-wrappers}"
out_host=$(cd "${OUT_DIR:-wrappers}" && pwd)

if [ -n "${IMAGE:-}" ]; then
    pkg=/pkg
    out=/out
    rscript() {
        docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e PKG="$pkg" \
            -v "$pkg_host:/pkg:ro" -v "$out_host:/out" -w /pkg \
            "$IMAGE" Rscript "$@"
    }
else
    pkg=$pkg_host
    out=$out_host
    export PKG=$pkg
    rscript() { Rscript "$@"; }
fi
cli() { rscript -e 'BiocJobs::biocjobsCLI()' "$@"; }

if [ -n "${JOB_NAMES:-}" ]; then
    names=$JOB_NAMES
else
    names=$(rscript -e \
        'cat(names(BiocJobs::findJobs(Sys.getenv("PKG"))), sep = "\n")')
fi
if [ -z "$names" ]; then
    echo "::error::No jobs declared under ${PACKAGE_DIR:-.}/inst/biocjobs."
    exit 1
fi

cli validate "$pkg"

for job in $names; do
    echo "::group::$job"
    mkdir -p "$out_host/$job"
    for target in galaxy tes nextflow wdl htcondor; do
        case $target in
            galaxy)   ext=xml ;;
            tes)      ext=tes.json ;;
            nextflow) ext=nf ;;
            wdl)      ext=wdl ;;
            htcondor) ext=sub ;;
        esac
        cli "$target" "$pkg" "$job" --out "$out/$job/$job.$ext" \
            ${PINNED:+--image "$PINNED"}
    done
    echo "::endgroup::"
done

cli manifest "$pkg" --out "$out/manifest.json"
find "$out_host" -type f | sort
