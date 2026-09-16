#!/usr/bin/env bash
# Lint every Galaxy tool under WRAPPERS_DIR, then test those with staged
# test data.
#
#   WRAPPERS_DIR    directory written by generate.sh
#   GALAXY_BRANCH   Galaxy branch to test against (default: release_26.1)
#   PYTHON_VERSION  Python for that Galaxy (default: 3.11)
set -euo pipefail

dir=${WRAPPERS_DIR:?}
mapfile -t tools < <(find "$dir" -name '*.xml' | sort)
if [ "${#tools[@]}" -eq 0 ]; then
    echo "::error::No Galaxy tools under $dir."
    exit 1
fi

planemo lint --report_level all --fail_level error "${tools[@]}"

status=0
for tool in "${tools[@]}"; do
    job=$(basename "$(dirname "$tool")")
    # Galaxy fails hard on a <tests> block whose files were never staged.
    if [ ! -d "$(dirname "$tool")/test-data" ]; then
        echo "::warning::$job has no staged test data; lint only."
        continue
    fi
    echo "::group::planemo test $job"
    # --docker runs the tool in the image the wrapper declares; the image
    # is already on this runner, so Galaxy does not pull.
    planemo test \
        --docker \
        --no_dependency_resolution \
        --no_conda_auto_init \
        --galaxy_branch "${GALAXY_BRANCH:-release_26.1}" \
        --galaxy_python_version "${PYTHON_VERSION:-3.11}" \
        --test_output "$dir/$job/test-report.html" \
        --test_output_json "$dir/$job/test-report.json" \
        "$tool" || status=$?
    echo "::endgroup::"
done
exit $status
