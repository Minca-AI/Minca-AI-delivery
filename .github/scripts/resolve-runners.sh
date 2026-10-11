#!/usr/bin/env bash
# Turn the `pool` input of ci.yml into the runner labels of its jobs.
#
# Precedence, highest first:
#   1. runs-on-override: this repository's self-test only.
#   2. The caller repository's RUNNER_CI / RUNNER_LARGE variables (1.4.0+): JSON
#      arrays of runner labels, e.g. '["ubuntu-latest"]', set while the fleet is
#      down and deleted to return to it.
#   3. The fleet pools [self-hosted, ci] / [self-hosted, large]. The fleet matches
#      label sets exactly, so a free-form label would queue forever instead of
#      failing; the shape check below turns a mistyped variable into an error.
#
# Env: POOL, OVERRIDE, RUNNER_CI, RUNNER_LARGE, GITHUB_OUTPUT.
# Outputs: runner (labels of the pool jobs), large (labels of test:integration).
set -euo pipefail

case "${POOL:-}" in
  ci|large) ;;
  *) echo "::error::pool must be 'ci' or 'large' (got '${POOL:-}')"; exit 1 ;;
esac

ci='["self-hosted","ci"]'
large='["self-hosted","large"]'
if [ -n "${OVERRIDE:-}" ]; then
  ci="$OVERRIDE"
  large="$OVERRIDE"
else
  [ -z "${RUNNER_CI:-}" ] || ci="$RUNNER_CI"
  [ -z "${RUNNER_LARGE:-}" ] || large="$RUNNER_LARGE"
fi

for labels in "$ci" "$large"; do
  if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' \
      <<<"$labels" >/dev/null 2>&1; then
    echo "::error::runner labels must be a non-empty JSON array of strings, e.g. [\"ubuntu-latest\"] (got '$labels')"
    exit 1
  fi
done

runner="$ci"
if [ "$POOL" = large ]; then
  runner="$large"
fi
{
  echo "runner=$runner"
  echo "large=$large"
} >> "$GITHUB_OUTPUT"
echo "runner=$runner large=$large"
