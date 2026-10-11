#!/usr/bin/env bash
# Unit tests for .github/scripts/resolve-runners.sh.
# No network, no GitHub: the script reads its env and writes two outputs.
#
# Cases: the fleet defaults per pool, the RUNNER_CI / RUNNER_LARGE variables, the
# precedence of runs-on-override, and every rejection (bad pool, labels that are
# not a non-empty JSON array of strings), which must leave no output behind.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../.github/scripts/resolve-runners.sh"
FLEET_CI='["self-hosted","ci"]'
FLEET_LARGE='["self-hosted","large"]'
HOSTED='["ubuntu-latest"]'
BIG='["self-hosted","large","x64"]'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUTPUTS="$TMP/github_output"

PASSED=0
FAILED=0
OUT=""
RC=0

# run_resolve <pool> <override> <runner_ci> <runner_large>: sets OUT, RC and the OUTPUTS file.
run_resolve() {
  : > "$OUTPUTS"
  set +e
  OUT="$(POOL="$1" OVERRIDE="$2" RUNNER_CI="$3" RUNNER_LARGE="$4" GITHUB_OUTPUT="$OUTPUTS" bash "$SCRIPT" 2>&1)"
  RC=$?
  set -e
}

pass() { echo "[OK]   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "[FAIL] $1"; echo "       rc=$RC out=$OUT"; FAILED=$((FAILED + 1)); }

# expect_ok <desc> <pool> <override> <runner_ci> <runner_large> <runner> <large>
expect_ok() {
  run_resolve "$2" "$3" "$4" "$5"
  if [[ "$RC" -eq 0 && "$(grep -cxF "runner=$6" "$OUTPUTS")" -eq 1 && "$(grep -cxF "large=$7" "$OUTPUTS")" -eq 1 && "$(wc -l <"$OUTPUTS")" -eq 2 ]]; then
    pass "$1"
  else
    fail "$1"
  fi
}

# expect_fail <desc> <pool> <override> <runner_ci> <runner_large> <substring>
expect_fail() {
  run_resolve "$2" "$3" "$4" "$5"
  if [[ "$RC" -eq 1 && "$OUT" == *"::error::"* && "$OUT" == *"$6"* && ! -s "$OUTPUTS" ]]; then
    pass "$1"
  else
    fail "$1"
  fi
}

expect_ok "pool ci on the fleet" ci "" "" "" "$FLEET_CI" "$FLEET_LARGE"
expect_ok "pool large on the fleet" large "" "" "" "$FLEET_LARGE" "$FLEET_LARGE"
expect_ok "RUNNER_CI replaces the ci pool only" ci "" "$HOSTED" "" "$HOSTED" "$FLEET_LARGE"
expect_ok "RUNNER_LARGE replaces the large pool only" large "" "" "$HOSTED" "$HOSTED" "$HOSTED"
expect_ok "pool ci ignores RUNNER_LARGE for its own jobs" ci "" "" "$HOSTED" "$FLEET_CI" "$HOSTED"
expect_ok "pool large ignores RUNNER_CI" large "" "$HOSTED" "" "$FLEET_LARGE" "$FLEET_LARGE"
expect_ok "both variables set" ci "" "$HOSTED" "$BIG" "$HOSTED" "$BIG"
expect_ok "a longer label set is kept verbatim" ci "" "$BIG" "" "$BIG" "$FLEET_LARGE"
expect_ok "runs-on-override wins over the variables" ci "$HOSTED" "$BIG" "$BIG" "$HOSTED" "$HOSTED"
expect_ok "runs-on-override wins on the large pool too" large "$HOSTED" "" "$BIG" "$HOSTED" "$HOSTED"

expect_fail "an unknown pool is refused" medium "" "" "" "pool must be 'ci' or 'large'"
expect_fail "an empty pool is refused" "" "" "" "" "pool must be 'ci' or 'large'"
expect_fail "a bare label is refused" ci "" "ubuntu-latest" "" "JSON array"
expect_fail "a JSON string is refused" ci "" '"ubuntu-latest"' "" "JSON array"
expect_fail "an empty array is refused" ci "" '[]' "" "JSON array"
expect_fail "an array with a number is refused" ci "" '["self-hosted", 4]' "" "JSON array"
expect_fail "an array with an empty label is refused" ci "" '[""]' "" "JSON array"
expect_fail "an object is refused" ci "" '{"labels":["ci"]}' "" "JSON array"
expect_fail "a bad RUNNER_LARGE fails a ci run too" ci "" "" "large" "JSON array"
expect_fail "a bad override is refused" ci "garbage" "$HOSTED" "" "JSON array"

echo "passed=$PASSED failed=$FAILED"
[[ "$FAILED" -eq 0 ]]
