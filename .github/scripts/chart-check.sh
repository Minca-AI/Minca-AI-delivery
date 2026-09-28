#!/usr/bin/env bash
# Validate charts/minca-service: helm lint and render every fixture under ci/,
# run the helm-unittest suites, and check the rendered objects with kubeconform
# against the Kubernetes version of the target clusters plus the CRD catalog
# (ExternalSecret). Runs the same locally and in self-test.
set -euo pipefail

CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../charts/minca-service" && pwd)"
KUBE_VERSION="${KUBE_VERSION:-1.33.0}"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

for values in "$CHART"/ci/*.yaml; do
  echo "== $(basename "$values")"
  helm lint --strict "$CHART" -f "$values"
  helm template fixture "$CHART" -f "$values" |
    kubeconform -strict -summary -kubernetes-version "$KUBE_VERSION" \
      -schema-location default -schema-location "$CRD_SCHEMAS"
done

helm unittest "$CHART"
