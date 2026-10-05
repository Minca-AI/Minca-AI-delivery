#!/usr/bin/env bash
# Pre-build fixture: runs in the working directory, with no AWS session.
set -euo pipefail
[ "$(basename "$PWD")" = fixtures ] || { echo "cwd is $PWD, want .../fixtures" >&2; exit 1; }
# The credentials, and every other way to find or mint an AWS identity (the runner's OIDC token
# endpoint is present when the job holds id-token: write).
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_ROLE_ARN          AWS_WEB_IDENTITY_TOKEN_FILE ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN          AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_CREDENTIALS_RELATIVE_URI; do
  [ -z "${!v+x}" ] || { echo "$v is set: the step must run without credentials" >&2; exit 1; }
done
echo "pre-build fixture: clean environment in $PWD"
