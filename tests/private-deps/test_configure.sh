#!/usr/bin/env bash
# Unit test for actions/private-deps/configure.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../../actions/private-deps/configure.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

check() {
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1 (expected '$3', got '$2')"
    fail=1
  else
    echo "ok: $1"
  fi
}

# No token: success, nothing exported.
: > "$tmp/env1"
TOKEN="" GITHUB_ENV="$tmp/env1" bash "$script" >/dev/null
check "empty token exports nothing" "$(wc -c < "$tmp/env1" | tr -d ' ')" "0"

# Token: three exports, scoped to the Minca-AI org only.
: > "$tmp/env2"
TOKEN="abc123" GITHUB_ENV="$tmp/env2" bash "$script" >/dev/null
check "token exports three lines" "$(wc -l < "$tmp/env2" | tr -d ' ')" "3"
check "rewrite target carries the token" \
  "$(grep -c '^GIT_CONFIG_KEY_0=url.https://x-access-token:abc123@github.com/Minca-AI/.insteadOf$' "$tmp/env2")" "1"
check "rewrite source is the org only" \
  "$(grep -c '^GIT_CONFIG_VALUE_0=https://github.com/Minca-AI/$' "$tmp/env2")" "1"

# Whitespace in the token is refused (it would corrupt the env file).
: > "$tmp/env3"
if TOKEN=$'a b' GITHUB_ENV="$tmp/env3" bash "$script" >/dev/null 2>&1; then
  echo "FAIL: whitespace token accepted"; fail=1
else
  echo "ok: whitespace token refused"
fi

# A pre-set GIT_CONFIG_COUNT is never overwritten.
: > "$tmp/env4"
if GIT_CONFIG_COUNT=1 TOKEN="abc" GITHUB_ENV="$tmp/env4" bash "$script" >/dev/null 2>&1; then
  echo "FAIL: existing GIT_CONFIG_COUNT overwritten"; fail=1
else
  echo "ok: existing GIT_CONFIG_COUNT refused"
fi

exit "$fail"
