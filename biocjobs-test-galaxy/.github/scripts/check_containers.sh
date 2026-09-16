#!/usr/bin/env bash
# Check that each tool declares one Docker container and that it provides /bin/bash,
# which Galaxy uses to start jobs. Needs Docker and galaxy-tool-util.
#
# Usage: check_containers.sh DIRECTORY [DIRECTORY ...]
set -euo pipefail

[ "$#" -gt 0 ] || { echo "usage: check_containers.sh DIRECTORY [DIRECTORY ...]" >&2; exit 2; }

parse_status=0
containers="$(python3 - "$@" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
from galaxy.tool_util.parser import get_tool_source

seen = set()
failed = False
for directory in sys.argv[1:]:
    for path in sorted(pathlib.Path(directory).rglob("*.xml")):
        if ET.parse(path).getroot().tag != "tool":
            continue
        source = get_tool_source(str(path))
        parse = getattr(source, "parse_requirements_and_containers", None) or source.parse_requirements
        docker = [c.identifier for c in parse()[1] if c.type == "docker"]
        if len(docker) != 1:
            print(f"::error file={path}::declare exactly one Docker container", file=sys.stderr)
            failed = True
        for image in docker:
            if image not in seen:
                seen.add(image)
                print(f"{image}\t{path}")
sys.exit(1 if failed else 0)
PY
)" || parse_status=1

status=$parse_status
while IFS=$'\t' read -r image path; do
  [ -n "$image" ] || continue
  if ! docker pull --quiet "$image" >/dev/null 2>&1; then
    echo "::error file=$path::cannot pull $image"
    status=1
  elif docker run --rm --network none --read-only --cap-drop ALL --entrypoint /bin/bash "$image" -c true >/dev/null 2>&1; then
    echo "ok  $image"
  else
    echo "::error file=$path::$image has no /bin/bash"
    status=1
  fi
done <<<"$containers"

exit "$status"
