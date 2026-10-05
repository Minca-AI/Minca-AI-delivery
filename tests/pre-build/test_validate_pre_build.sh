#!/usr/bin/env bash
# Unit tests for actions/pre-build/validate-pre-build.sh.
# No network, no Docker, no AWS: the script reads its env and a scratch checkout, and prints a verdict.
#
# Cases: no input, accepted scripts, every path rejection rule (absolute, `..`, odd characters,
# missing file, directory, symlink out of the checkout), the role rules, and the event gating of the
# AWS session (a pull request never assumes the role).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/../../actions/pre-build/validate-pre-build.sh"
ROLE='arn:aws:iam::123456789012:role/gnp-dev-codifier-model-read'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CHECKOUT="$TMP/checkout"
mkdir -p "$CHECKOUT/tools" "$CHECKOUT/some-dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CHECKOUT/tools/fetch.sh"
printf 'x\n' > "$TMP/outside.sh"
SYMLINK_OK=true
ln -s "$TMP/outside.sh" "$CHECKOUT/tools/escape.sh" 2>/dev/null || SYMLINK_OK=false
[[ -L "$CHECKOUT/tools/escape.sh" ]] || SYMLINK_OK=false

PASSED=0
FAILED=0
OUT=""
RC=0
OUTPUTS="$TMP/github_output"

# run_validate <script> <role> <event> [<workdir>]: sets OUT (stdout+stderr), RC and the OUTPUTS file.
run_validate() {
  : > "$OUTPUTS"
  set +e
  OUT="$(SCRIPT="$1" ROLE_ARN="$2" EVENT="$3" WORKDIR="${4:-$CHECKOUT}" GITHUB_OUTPUT="$OUTPUTS" bash "$VALIDATOR" 2>&1)"
  RC=$?
  set -e
}

pass() { echo "[OK]   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "[FAIL] $1"; echo "       rc=$RC out=$OUT"; FAILED=$((FAILED + 1)); }

# expect_ok <desc> <script> <role> <event> <run> <assume>
expect_ok() {
  run_validate "$2" "$3" "$4"
  if [[ "$RC" -eq 0 && "$(grep -c '^run='"$5"'$' "$OUTPUTS")" -eq 1 && "$(grep -c '^assume='"$6"'$' "$OUTPUTS")" -eq 1 ]]; then
    pass "$1"
  else
    fail "$1"
  fi
}

# expect_fail <desc> <script> <role> <event> [<substring> [<workdir>]]
expect_fail() {
  run_validate "$2" "$3" "$4" "${6:-}"
  if [[ "$RC" -eq 1 && "$OUT" == *"::error::pre-build:"* && "$OUT" == *"refusing to build"* && "$OUT" == *"${5:-}"* && ! -s "$OUTPUTS" ]]; then
    pass "$1"
  else
    fail "$1"
  fi
}

expect_ok "no script and no role does nothing" "" "" push false false
expect_fail "a role without a script is refused" "" "$ROLE" push "pre-build is empty"
expect_ok "a plain script runs, no session" "tools/fetch.sh" "" push true false
expect_ok "a script with a role assumes the session on push" "tools/fetch.sh" "$ROLE" push true true
expect_ok "a script with a role assumes the session on workflow_dispatch" "tools/fetch.sh" "$ROLE" workflow_dispatch true true
expect_ok "a script with a role assumes the session on schedule" "tools/fetch.sh" "$ROLE" schedule true true
expect_ok "a script with a role assumes the session on release" "tools/fetch.sh" "$ROLE" release true true
# The session is assumed on an allow-list of events: every other event runs the script without it.
for event in pull_request pull_request_target workflow_run issue_comment pull_request_review pull_request_review_comment merge_group repository_dispatch workflow_call discussion ""; do
  expect_ok "event '$event' never assumes the role" "tools/fetch.sh" "$ROLE" "$event" true false
done
expect_fail "an absolute path is refused" "/etc/passwd" "" push "relative path"
expect_fail "a parent segment is refused" "tools/../tools/fetch.sh" "" push ".."
expect_fail "a leading parent segment is refused" "../outside.sh" "" push "relative path"
expect_fail "a leading dash is refused" "-x" "" push "relative path"
expect_fail "a space is refused" "tools/fe tch.sh" "" push "relative path"
expect_fail "a shell metacharacter is refused" 'tools/fetch.sh;id' "" push "relative path"
expect_fail "a dollar expansion is refused" "tools/\$HOME.sh" "" push "relative path"
expect_fail "an empty segment is refused" "tools//fetch.sh" "" push "empty"
expect_fail "a leading dot segment is refused" "./tools/fetch.sh" "" push "relative path"
expect_fail "an inner dot segment is refused" "tools/./fetch.sh" "" push "empty"
expect_fail "a missing file is refused" "tools/missing.sh" "" push "not a regular file"
expect_fail "a directory is refused" "some-dir" "" push "not a regular file"
if [[ "$SYMLINK_OK" == true ]]; then
  expect_fail "a symlink out of the checkout is refused" "tools/escape.sh" "" push "outside the working directory"
else
  echo "[SKIP] symlink case: this host cannot create symlinks"
fi
expect_fail "a working directory with a parent segment is refused" "tools/fetch.sh" "" push "working-directory" "$CHECKOUT/../checkout"
expect_fail "a role that is not an ARN is refused" "tools/fetch.sh" "gnp-dev-role" push "not an IAM role ARN"
expect_fail "a user ARN is refused" "tools/fetch.sh" "arn:aws:iam::123456789012:user/someone" push "not an IAM role ARN"
expect_fail "an ARN with a short account id is refused" "tools/fetch.sh" "arn:aws:iam::1234:role/x" push "not an IAM role ARN"
expect_fail "an ARN with a parent segment is refused" "tools/fetch.sh" "arn:aws:iam::123456789012:role/a/../b" push "not an IAM role ARN"
expect_fail "an ARN with a space is refused" "tools/fetch.sh" "arn:aws:iam::123456789012:role/a b" push "not an IAM role ARN"

echo "passed=$PASSED failed=$FAILED"
[[ "$FAILED" -eq 0 ]]
