#!/usr/bin/env bash
# Export GIT_CONFIG_* so git rewrites https://github.com/Minca-AI/ to an
# authenticated URL for the rest of the job. Reads TOKEN from the environment.
# Writes to $GITHUB_ENV (override with GITHUB_ENV for tests); never to disk config.
set -euo pipefail

if [ -z "${TOKEN:-}" ]; then
  echo "No private-deps token given: private repositories stay unreachable."
  exit 0
fi

case "$TOKEN" in
  *[[:space:]]*) echo "::error::the private-deps token contains whitespace"; exit 1 ;;
esac

echo "::add-mask::$TOKEN"

env_file="${GITHUB_ENV:?GITHUB_ENV is not set}"
if [ -n "${GIT_CONFIG_COUNT:-}" ]; then
  echo "::error::GIT_CONFIG_COUNT is already set; refusing to overwrite it"
  exit 1
fi

{
  echo "GIT_CONFIG_COUNT=1"
  echo "GIT_CONFIG_KEY_0=url.https://x-access-token:${TOKEN}@github.com/Minca-AI/.insteadOf"
  echo "GIT_CONFIG_VALUE_0=https://github.com/Minca-AI/"
} >> "$env_file"
echo "git will use the token for https://github.com/Minca-AI/ for the rest of this job."
