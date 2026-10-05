#!/usr/bin/env bash
# Pre-build fixture: runs in the working directory, with no AWS session.
set -euo pipefail
[ "$(basename "$PWD")" = fixtures ] || { echo "cwd is $PWD, want .../fixtures" >&2; exit 1; }
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  [ -z "${!v+x}" ] || { echo "$v is set: the step must run without credentials" >&2; exit 1; }
done
echo "pre-build fixture: clean environment in $PWD"
