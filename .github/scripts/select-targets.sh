#!/usr/bin/env bash
# Turn the `targets` input into the job matrix of ci.yml.
#
# A target the Taskfile defines is kept. A missing REQUIRED target (design 5.1:
# lint, typecheck, test) fails the run: a repository that silently skips its
# tests would show a green check for work that never ran. A missing optional
# target is skipped with a notice.
#
# Env: TARGETS (space-separated), GITHUB_OUTPUT. Runs in the project directory.
set -euo pipefail

REQUIRED=" lint typecheck test "

available="$(task --list-all --json | jq -r '.tasks[].name')"
selected=()
for target in $TARGETS; do
  if ! [[ "$target" =~ ^[A-Za-z0-9:_-]+$ ]]; then
    echo "::error::invalid target name '$target'"; exit 1
  fi
  if grep -qxF "$target" <<<"$available"; then
    selected+=("$target")
  elif [[ "$REQUIRED" == *" $target "* ]]; then
    echo "::error::required target '$target' is not defined in the Taskfile"; exit 1
  else
    echo "::notice::optional target '$target' is not defined; skipped"
  fi
done

json="$(printf '%s\n' "${selected[@]}" | jq -R . | jq -cs 'map(select(. != ""))')"
echo "targets=$json" >> "$GITHUB_OUTPUT"
echo "targets: $json"
