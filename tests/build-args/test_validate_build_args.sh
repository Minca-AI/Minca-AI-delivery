#!/usr/bin/env bash
# Unit tests for actions/build-smoke-push/validate-build-args.sh.
# No network, no Docker: the script reads BUILD_ARGS and prints a verdict.
#
# Cases: accepted shapes, every rejection rule, several faults reported in one
# run, and that no value ever appears in the output.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../actions/build-smoke-push/validate-build-args.sh"
SENTINEL='s3nt1nel-v4lue'

PASSED=0
FAILED=0
OUT=""
RC=0

# Runs the validator with $1 as BUILD_ARGS; sets OUT (stdout+stderr) and RC.
run_validate() {
  set +e
  OUT="$(BUILD_ARGS="$1" bash "$SCRIPT" 2>&1)"
  RC=$?
  set -e
}

pass() { echo "[OK]   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "[FAIL] $1"; echo "       rc=$RC out=$OUT"; FAILED=$((FAILED + 1)); }

# expect_ok <desc> <input> <expected success line>
expect_ok() {
  run_validate "$2"
  if [[ "$RC" -eq 0 && "$OUT" == "$3" ]]; then pass "$1"; else fail "$1"; fi
}

# expect_fail <desc> <input> <expected number of faulty lines> [<substring>]
expect_fail() {
  local count
  run_validate "$2"
  count="$(grep -c '^::error::build-args line ' <<<"$OUT" || true)"
  if [[ "$RC" -eq 1 && "$count" -eq "$3" && "$OUT" != *"build-args: none"* \
        && "$OUT" == *"refusing to build"* && "$OUT" == *"${4:-}"* ]]; then
    pass "$1"
  else
    fail "$1 (want $3 fault line(s), got $count)"
  fi
}

# no_leak <desc> <input>: the sentinel must not appear anywhere in the output.
no_leak() {
  run_validate "$2"
  if [[ "$OUT" != *"$SENTINEL"* ]]; then pass "$1"; else fail "$1 (value leaked)"; fi
}

# 1-3: nothing to forward
set +e
OUT="$(env -u BUILD_ARGS bash "$SCRIPT" 2>&1)"; RC=$?
set -e
if [[ "$RC" -eq 0 && "$OUT" == "build-args: none" ]]; then pass "unset input is accepted"; else fail "unset input is accepted"; fi
expect_ok "empty input is accepted" "" "build-args: none"
expect_ok "whitespace-only lines are skipped" $'\n  \n\t\n' "build-args: none"

# 4-11: accepted shapes
expect_ok "one argument" "A=1" "build-args: A"
expect_ok "two arguments keep input order" $'A=1\nB=2' "build-args: A B"
expect_ok "CRLF line endings are stripped" $'A=1\r\nB=2\r\n' "build-args: A B"
expect_ok "blank lines between arguments" $'A=1\n\nB=2\n' "build-args: A B"
expect_ok "empty value is valid" "A=" "build-args: A"
expect_ok "value may hold =, comma and inner spaces" "A=x=y, z,w" "build-args: A"
expect_ok "leading underscore and digits in a name" "_A1=x" "build-args: _A1"
expect_ok "names are case-sensitive" $'a=1\nA=2' "build-args: a A"

# 12-17: malformed lines
expect_fail "empty name" "=x" 1 "line 1"
expect_fail "name starting with a digit" "1A=x" 1
expect_fail "name with a dash" "A-B=x" 1
expect_fail "leading space makes a bad name" " A=x" 1
expect_fail "line without =" "A" 1 "NAME=value"
expect_fail "comment lines are not supported" "# comment" 1

# 18: duplicates
expect_fail "duplicate name" $'A=1\nA=2' 1 "duplicate of line 1"
expect_fail "duplicate is reported at the second line" $'A=1\nA=2' 1 "line 2"

# 19-21: credential-like names
expect_fail "credential-like name" "GH_TOKEN=x" 1 "credential"
expect_fail "credential check is case-insensitive" "db_password=x" 1
for name in MY_SECRET HTPASSWD GCP_CREDENTIALS PRIVATE_KEY NPM_APIKEY X_API_KEY AWS_ACCESS_KEY_ID; do
  expect_fail "credential word in $name" "$name=x" 1 "credential"
done

# 22: BUILDKIT_*
expect_fail "BUILDKIT_ name" "BUILDKIT_SYNTAX=docker/dockerfile:1" 1 "BUILDKIT_"
expect_fail "BUILDKIT_ check is case-insensitive" "buildkit_inline_cache=1" 1 "BUILDKIT_"

# 23-24: values the build action would rewrite
expect_fail "value that is a quoted string" 'A="x"' 1 "double quote"
expect_fail "value with an embedded quote" 'A=x,"y"' 1 "double quote"
expect_fail "trailing space in value" "A=x " 1 "whitespace"
expect_fail "leading space in value" "A= x" 1 "whitespace"
expect_fail "trailing tab in value" $'A=x\t' 1 "whitespace"

# 25: every fault reported in one run
expect_fail "all faulty lines are reported" $'1A=x\nGH_TOKEN=y\nA=ok\nA=again' 3 "3 fault(s)"
run_validate $'1A=x\nGH_TOKEN=y\nA=ok\nA=again'
if [[ "$OUT" == *"line 1:"* && "$OUT" == *"line 2:"* && "$OUT" == *"line 4:"* && "$OUT" != *"line 3:"* ]]; then
  pass "faults name lines 1, 2 and 4"
else
  fail "faults name lines 1, 2 and 4"
fi

# 26: values never reach the output
no_leak "credential-like name with a value" "GH_TOKEN=$SENTINEL"
no_leak "bare value line" "$SENTINEL"
no_leak "bad name containing the value" "-$SENTINEL=x"
no_leak "duplicate with the value" $'A='"$SENTINEL"$'\nA='"$SENTINEL"
no_leak "quoted value" "A=\"$SENTINEL\""
no_leak "value with trailing space" "A=$SENTINEL "
no_leak "accepted value" "A=$SENTINEL"

echo "passed=$PASSED failed=$FAILED"
[[ "$FAILED" -eq 0 ]]
