#!/usr/bin/env bash
# Write a kubeconfig for the galaxy-deployer account. Run with cluster admin credentials.
#
# Usage: make-kubeconfig.sh [OUTPUT]
set -euo pipefail

output="${1:-galaxy-deployer.kubeconfig}"
namespace="testgalaxy"
secret="galaxy-deployer-token"

server="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
ca_data="$(kubectl -n "$namespace" get secret "$secret" -o jsonpath='{.data.ca\.crt}')"
token="$(kubectl -n "$namespace" get secret "$secret" -o jsonpath='{.data.token}' | base64 --decode)"
[ -n "$server" ] && [ -n "$token" ] || { echo "apply deploy/namespace-setup.yaml first" >&2; exit 1; }

umask 077
cat > "$output" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: testgalaxy
    cluster:
      server: $server
      certificate-authority-data: $ca_data
users:
  - name: galaxy-deployer
    user:
      token: $token
contexts:
  - name: testgalaxy
    context:
      cluster: testgalaxy
      namespace: $namespace
      user: galaxy-deployer
current-context: testgalaxy
KUBECONFIG

echo "Wrote $output"
