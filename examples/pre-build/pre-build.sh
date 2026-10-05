#!/usr/bin/env bash
# Pre-build fixture of image.yml: puts a file into the build context, after proving it runs in the
# project directory with no AWS credentials.
set -euo pipefail
[ "$(basename "$PWD")" = pre-build ] || { echo "cwd is $PWD, want .../pre-build" >&2; exit 1; }
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [ -z "${!v+x}" ] || { echo "$v is set but no role was given" >&2; exit 1; }
done
mkdir -p generated
printf 'made by pre-build\n' > generated/greeting.txt
