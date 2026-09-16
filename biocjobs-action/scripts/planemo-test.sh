#!/usr/bin/env bash
# Lint every Galaxy tool under WRAPPERS_DIR and run the tests they declare
# in one planemo test run. Results go to the job summary.
#
#   WRAPPERS_DIR    directory written by generate.sh
#   REPORT_HTML     path for the planemo HTML report (default: planemo-report.html)
#   GALAXY_BRANCH   Galaxy branch to test against (default: release_26.1)
#   PYTHON_VERSION  Python for that Galaxy (default: 3.11)
set -euo pipefail

dir=${WRAPPERS_DIR:?}
report=${REPORT_HTML:-planemo-report.html}
# Wrappers sit at <job>/<job>.xml; deeper matches would be staged test data.
mapfile -t tools < <(find "$dir" -mindepth 2 -maxdepth 2 -name '*.xml' | sort)
if [ "${#tools[@]}" -eq 0 ]; then
    echo "::error::No Galaxy tools under $dir."
    exit 1
fi

# Print the test-data files a tool's tests name that were not staged.
missing_test_files() {
    python3 - "$1" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
tool = pathlib.Path(sys.argv[1])
root = ET.parse(tool).getroot()
data = {p.get("name") for p in root.iter("param") if p.get("type") == "data"}
names = set()
for test in root.iter("test"):
    for param in test.iter("param"):
        if param.get("name") in data and param.get("value"):
            names.update(v.strip() for v in param.get("value").split(","))
    for output in test.iter("output"):
        if output.get("file"):
            names.add(output.get("file"))
for name in sorted(names):
    if not (tool.parent / "test-data" / name).is_file():
        print(name)
PY
}

status=0
rows=$(mktemp)
testable=()
for tool in "${tools[@]}"; do
    job=$(basename "$(dirname "$tool")")
    tool_id=$(python3 -c 'import sys, xml.etree.ElementTree as ET; print(ET.parse(sys.argv[1]).getroot().get("id", ""))' "$tool")

    echo "::group::planemo lint $job"
    if planemo lint --report_level all --fail_level error "$tool"; then
        lint=passed
    else
        lint=failed
        status=1
    fi
    echo "::endgroup::"

    if ! grep -q '<test[ >]' "$tool"; then
        echo "::notice::$job declares no tests; it was linted only."
        state="no tests declared"
    else
        missing=$(missing_test_files "$tool" | paste -sd ',' - | sed 's/,/, /g')
        if [ -n "$missing" ]; then
            echo "::error::$job: test files missing from the package: $missing. Paths under tests: in the job YAML are relative to the package root."
            state="not run: missing $missing"
            status=1
        else
            state=test
            testable+=("$tool")
        fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$job" "$tool_id" "$lint" "$state" >> "$rows"
done

json=$(mktemp)
if [ "${#testable[@]}" -gt 0 ]; then
    echo "::group::planemo test"
    # --docker runs each tool in the image its wrapper declares; the images
    # are already on this runner, so Galaxy does not pull.
    planemo test \
        --docker \
        --no_dependency_resolution \
        --no_conda_auto_init \
        --galaxy_branch "${GALAXY_BRANCH:-release_26.1}" \
        --galaxy_python_version "${PYTHON_VERSION:-3.11}" \
        --test_output "$report" \
        --test_output_json "$json" \
        "${testable[@]}" || status=1
    echo "::endgroup::"
    if [ -f "$report" ]; then
        echo "report=$report" >> "${GITHUB_OUTPUT:-/dev/null}"
    fi
fi

python3 - "$rows" "$json" <<'PY' >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
import collections, json, sys
counts = collections.defaultdict(lambda: [0, 0])
try:
    for test in json.load(open(sys.argv[2])).get("tests", []):
        data = test.get("data", {})
        entry = counts[data.get("tool_id", "")]
        entry[1] += 1
        entry[0] += data.get("status") == "success"
except (OSError, ValueError):
    pass
print("### Galaxy tools\n")
print("| Tool | planemo lint | planemo test |")
print("|---|---|---|")
for line in open(sys.argv[1]):
    job, tool_id, lint, state = line.rstrip("\n").split("\t")
    if state == "test":
        passed, total = counts[tool_id]
        if not total:
            state = "failed: no results, see the log"
        elif passed == total:
            state = f"passed ({passed} of {total})"
        else:
            state = f"failed ({passed} of {total} passed)"
    print(f"| `{job}` | {lint} | {state} |")
PY
rm -f "$rows" "$json"
exit $status
