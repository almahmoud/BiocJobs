#!/usr/bin/env bash
# Generate every BiocJobs wrapper for one package.
#
#   PACKAGE_DIR  package source directory (default: .)
#   OUT_DIR      output directory (default: ./wrappers)
#   JOB_NAMES    space-separated job names; empty means all
#   JOBS_FILE    "<job>\t<image>" lines from plan_jobs.py, used instead of
#                JOB_NAMES. A job with an image is generated inside it and
#                keeps the container its YAML declares.
#   IMAGE        run R inside this image; empty uses the host Rscript
#   PINNED       image reference written into the wrappers via --image
set -euo pipefail

pkg_host=$(cd "${PACKAGE_DIR:-.}" && pwd)
mkdir -p "${OUT_DIR:-wrappers}"
out_host=$(cd "${OUT_DIR:-wrappers}" && pwd)

# Run R inside an image, or with the host Rscript when the image is empty.
use() {
    run_image=$1
    if [ -n "$run_image" ]; then
        pkg=/pkg
        out=/out
    else
        pkg=$pkg_host
        out=$out_host
    fi
}
rscript() {
    if [ -n "$run_image" ]; then
        docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e PKG="$pkg" \
            -v "$pkg_host:/pkg:ro" -v "$out_host:/out" -w /pkg \
            "$run_image" Rscript "$@"
    else
        PKG=$pkg Rscript "$@"
    fi
}
cli() { rscript -e 'BiocJobs::biocjobsCLI()' "$@"; }

names=()
declared=()
if [ -n "${JOBS_FILE:-}" ]; then
    while IFS=$'\t' read -r job image; do
        names+=("$job")
        declared+=("$image")
    done < "$JOBS_FILE"
else
    use "${IMAGE:-}"
    if [ -n "${JOB_NAMES:-}" ]; then
        listing=$(printf '%s\n' $JOB_NAMES)
    else
        listing=$(rscript -e \
            'cat(names(BiocJobs::findJobs(Sys.getenv("PKG"))), sep = "\n")')
    fi
    while read -r job; do
        [ -z "$job" ] || { names+=("$job"); declared+=(""); }
    done <<<"$listing"
fi
if [ "${#names[@]}" -eq 0 ]; then
    echo "::error::No jobs declared under ${PACKAGE_DIR:-.}/inst/biocjobs."
    exit 1
fi

# A declared container must provide R and BiocJobs: the wrappers run
# BiocJobs::execJob() inside it.
default_image=${IMAGE:-}
for i in "${!names[@]}"; do
    image=${declared[$i]}
    [ -n "$image" ] || continue
    [ -n "$default_image" ] || default_image=$image
    if ! docker image inspect "$image" >/dev/null 2>&1 \
        && ! docker pull --quiet "$image" >/dev/null; then
        echo "::error::Cannot pull $image, the container ${names[$i]} declares."
        exit 1
    fi
    use "$image"
    if ! rscript -e 'if (!requireNamespace("BiocJobs", quietly = TRUE)) quit(status = 1)'; then
        echo "::error::$image, the container ${names[$i]} declares, does not have BiocJobs installed."
        exit 1
    fi
done
# Jobs without a declared container need the built image or the host.
for image in "${declared[@]}"; do
    [ -n "$image" ] || default_image=${IMAGE:-}
done

use "$default_image"
cli validate "$pkg"

for i in "${!names[@]}"; do
    job=${names[$i]}
    echo "::group::$job"
    mkdir -p "$out_host/$job"
    flags=()
    if [ -n "${declared[$i]}" ]; then
        use "${declared[$i]}"
        echo "Using the container $job declares: ${declared[$i]}"
    else
        use "${IMAGE:-}"
        [ -z "${PINNED:-}" ] || flags=(--image "$PINNED")
    fi
    for target in galaxy tes nextflow wdl htcondor; do
        case $target in
            galaxy)   ext=xml ;;
            tes)      ext=tes.json ;;
            nextflow) ext=nf ;;
            wdl)      ext=wdl ;;
            htcondor) ext=sub ;;
        esac
        cli "$target" "$pkg" "$job" --out "$out/$job/$job.$ext" \
            ${flags[@]+"${flags[@]}"}
    done
    echo "::endgroup::"
done

use "$default_image"
cli manifest "$pkg" --out "$out/manifest.json"
find "$out_host" -type f | sort
