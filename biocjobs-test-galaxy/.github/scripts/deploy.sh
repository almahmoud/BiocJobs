#!/usr/bin/env bash
# Upgrade the test instance with deploy/values.yaml and the rendered tools, then check
# each tool is served at its version. Helm rolls back a failed upgrade.
#
# Usage: deploy.sh RENDERED_VALUES MANIFEST
set -euo pipefail

values="${1:?usage: deploy.sh RENDERED_VALUES MANIFEST}"
manifest="${2:?usage: deploy.sh RENDERED_VALUES MANIFEST}"
galaxy_url="https://testgalaxy.bioconductor.org"

helm repo add cloudve https://raw.githubusercontent.com/CloudVE/helm-charts/master --force-update >/dev/null
helm upgrade tgx cloudve/galaxy \
  --version 5.14.3 \
  --namespace testgalaxy \
  --values deploy/values.yaml \
  --values "$values" \
  --skip-crds \
  --rollback-on-failure \
  --timeout 15m

deadline=$((SECONDS + 600))
while :; do
  missing=0
  while IFS=$'\t' read -r tool_id version source; do
    [ -n "$tool_id" ] || continue
    served="$(curl -fsS --max-time 20 "$galaxy_url/api/tools/$tool_id" 2>/dev/null \
      | python3 -c 'import json, sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true)"
    if [ "$served" != "$version" ]; then
      missing=$((missing + 1))
      [ "$SECONDS" -lt "$deadline" ] || echo "::error::$tool_id ($source): expected version $version, served ${served:-nothing}"
    fi
  done < "$manifest"
  [ "$missing" -gt 0 ] || break
  [ "$SECONDS" -lt "$deadline" ] || exit 1
  sleep 15
done
while IFS=$'\t' read -r tool_id version source; do
  echo "Serving $tool_id $version ($source)"
done < "$manifest"
