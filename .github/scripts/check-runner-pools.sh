#!/usr/bin/env bash
# Guard of the runner pool contract (README "Runner pools", SECURITY.md rule 2).
#
# Reusable workflows: every `runs-on` that names a self-hosted pool reads the
# caller's RUNNER_CI or RUNNER_LARGE variable first, so a consumer leaves the
# fleet by setting a variable, never by editing a workflow.
# This repository's own workflows: no self-hosted label in any `runs-on`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
for f in .github/workflows/ci.yml .github/workflows/quality-guards.yml \
         .github/workflows/image.yml .github/workflows/promote.yml; do
  while IFS= read -r line; do
    case "$line" in
      *vars.RUNNER_CI*|*vars.RUNNER_LARGE*) ;;
      *) echo "::error file=$f::self-hosted runs-on without a RUNNER_* variable: $line"; status=1 ;;
    esac
  done < <(grep -E '^[[:space:]]*runs-on:.*self-hosted' "$f" || true)
  if ! grep -Eq '^[[:space:]]*runs-on:.*vars\.RUNNER_CI' "$f"; then
    echo "::error file=$f::no runs-on reads vars.RUNNER_CI"; status=1
  fi
done
for f in .github/workflows/self-test.yml .github/workflows/release.yml \
         .github/workflows/chart-release.yml; do
  if grep -Eq '^[[:space:]]*runs-on:.*self-hosted' "$f"; then
    echo "::error file=$f::this repository's own workflows run on GitHub-hosted runners only"; status=1
  fi
done
if ! grep -q 'self-hosted' .github/scripts/resolve-runners.sh; then
  echo "::error::resolve-runners.sh lost the fleet fallback"; status=1
fi
[ "$status" -eq 0 ] && echo "runner pools: ok"
exit "$status"
