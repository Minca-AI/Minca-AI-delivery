#!/usr/bin/env bash
# The BUMP_PIN_BEFORE_PUSH snippets are single-quoted on purpose: they expand
# $ATTEMPT inside the hook, not here.
# shellcheck disable=SC2016
# Unit tests for actions/bump-pin/bump-pin.sh against scratch git repositories.
# No network, no GitHub: the "deploy repo" is a local bare repository, and gh is
# a stub on PATH that records its arguments.
#
# Cases: first commit, idempotent re-run, race without conflict, race with a
# textual conflict, retry exhaustion, input validation, missing pins file, and
# pull-request mode.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../actions/bump-pin/bump-pin.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

DIGEST_A="sha256:$(printf 'a%.0s' {1..64})"
DIGEST_B="sha256:$(printf 'b%.0s' {1..64})"
DIGEST_C="sha256:$(printf 'c%.0s' {1..64})"
TAG_A="sha-$(printf '1%.0s' {1..40})"
TAG_B="sha-$(printf '2%.0s' {1..40})"
TAG_C="sha-$(printf '3%.0s' {1..40})"

PASSED=0
FAILED=0

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export BACKOFF_SECONDS=0

# A fresh bare "deploy repo" with one environment and two pinned services.
new_remote() {
  local remote="$SCRATCH/$1.git" seed="$SCRATCH/$1-seed"
  git init --quiet --bare --initial-branch=main "$remote"
  git init --quiet --initial-branch=main "$seed"
  mkdir -p "$seed/environments/dev"
  cat > "$seed/environments/dev/pins.yaml" <<EOF
# environments/dev/pins.yaml -- written only by promote.yml or a human revert
chart: 1.0.0
services:
  codifier:
    image: minca/gnp-codifier
    tag: sha-0000000000000000000000000000000000000000
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
  preprocessor:
    image: minca/mincaai-preprocessor-core
    tag: sha-0000000000000000000000000000000000000000
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
EOF
  git -C "$seed" add . && git -C "$seed" commit --quiet -m "seed"
  git -C "$seed" push --quiet "$remote" main
  echo "$remote"
}

# Pushes a commit to the remote from a second clone, as a competing promotion.
compete() {
  local remote="$1" service="$2" tag="$3" digest="$4" clone
  clone="$(mktemp -d "$SCRATCH/compete.XXXX")"
  git clone --quiet "$remote" "$clone"
  SERVICE="$service" TAG="$tag" DIGEST="$digest" yq -i \
    '.services[strenv(SERVICE)].tag = strenv(TAG) | .services[strenv(SERVICE)].digest = strenv(DIGEST)' \
    "$clone/environments/dev/pins.yaml"
  git -C "$clone" commit --quiet -am "competing promotion of $service"
  git -C "$clone" push --quiet origin main
}
export -f compete
export SCRATCH

run_bump() {
  REMOTE="$1" PINS_PATH=environments/dev/pins.yaml ENVIRONMENT=dev \
    SERVICE="$2" TAG="$3" DIGEST="$4" MODE="${MODE:-commit}" "$SCRIPT"
}

remote_value() { git -C "$1" show main:environments/dev/pins.yaml | yq "$2"; }
remote_commits() { git -C "$1" rev-list --count main; }

check() {
  local name="$1"; shift
  if "$@"; then PASSED=$((PASSED + 1)); echo "[OK]   $name"
  else FAILED=$((FAILED + 1)); echo "[FAIL] $name"; fi
}

test_first_commit() {
  local r; r="$(new_remote first)"
  run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  [ "$(remote_value "$r" .services.codifier.tag)" = "$TAG_A" ] &&
    [ "$(remote_value "$r" .services.codifier.digest)" = "$DIGEST_A" ] &&
    [ "$(remote_value "$r" .services.codifier.image)" = "minca/gnp-codifier" ] &&
    [ "$(remote_value "$r" .services.preprocessor.tag)" = "sha-0000000000000000000000000000000000000000" ] &&
    [ "$(git -C "$r" log -1 --format=%s main)" = "chore(pins): codifier $TAG_A [dev]" ] &&
    git -C "$r" show main:environments/dev/pins.yaml | grep -q '^# environments/dev/pins.yaml'
}

test_idempotent() {
  local r before; r="$(new_remote idem)"
  run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  before="$(remote_commits "$r")"
  run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  [ "$(remote_commits "$r")" = "$before" ]
}

test_race_without_conflict() {
  local r; r="$(new_remote race)"
  BUMP_PIN_BEFORE_PUSH='[ "$ATTEMPT" = 1 ] && compete "'"$r"'" preprocessor '"$TAG_B $DIGEST_B"' || true' \
    run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  [ "$(remote_value "$r" .services.codifier.tag)" = "$TAG_A" ] &&
    [ "$(remote_value "$r" .services.preprocessor.tag)" = "$TAG_B" ] &&
    [ "$(remote_commits "$r")" = 3 ]
}

test_race_with_conflict() {
  local r; r="$(new_remote conflict)"
  # The competitor rewrites the very lines we edit, so the rebase conflicts and
  # the pin must be re-applied on the new head. Ours lands last and wins.
  BUMP_PIN_BEFORE_PUSH='[ "$ATTEMPT" = 1 ] && compete "'"$r"'" codifier '"$TAG_C $DIGEST_C"' || true' \
    run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  [ "$(remote_value "$r" .services.codifier.tag)" = "$TAG_A" ] &&
    [ "$(remote_value "$r" .services.codifier.digest)" = "$DIGEST_A" ] &&
    [ "$(remote_commits "$r")" = 3 ]
}

test_retry_exhaustion() {
  local r; r="$(new_remote exhaust)"
  # A competitor lands before every attempt: after five the script must fail loudly.
  if BUMP_PIN_BEFORE_PUSH='compete "'"$r"'" preprocessor sha-$(printf "%040d" "$ATTEMPT") '"$DIGEST_B" \
    run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null 2>&1; then
    return 1
  fi
  [ "$(remote_value "$r" .services.codifier.tag)" != "$TAG_A" ]
}

test_rejects_bad_digest() {
  local r; r="$(new_remote baddigest)"
  ! run_bump "$r" codifier "$TAG_A" "sha256:nothex" >/dev/null 2>&1 &&
    [ "$(remote_commits "$r")" = 1 ]
}

test_missing_pins_file() {
  local r; r="$(new_remote missing)"
  ! REMOTE="$r" PINS_PATH=environments/prod/pins.yaml ENVIRONMENT=prod SERVICE=codifier \
    TAG="$TAG_A" DIGEST="$DIGEST_A" MODE=commit "$SCRIPT" >/dev/null 2>&1
}

test_pull_request_mode() {
  local r stubdir; r="$(new_remote prmode)"; stubdir="$SCRATCH/stub"
  mkdir -p "$stubdir"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh.log"\n' "$stubdir" > "$stubdir/gh"
  chmod +x "$stubdir/gh"
  PATH="$stubdir:$PATH" MODE=pull-request GH_REPO=Minca-AI/example \
    run_bump "$r" codifier "$TAG_A" "$DIGEST_A" >/dev/null
  [ "$(remote_commits "$r")" = 1 ] &&
    git -C "$r" show "pins/dev/codifier/$TAG_A:environments/dev/pins.yaml" | grep -q "$DIGEST_A" &&
    grep -q "pr create --repo Minca-AI/example --base main --head pins/dev/codifier/$TAG_A" "$stubdir/gh.log"
}

check "first promotion commits the pin and keeps comments" test_first_commit
check "re-promoting the same pin is a no-op" test_idempotent
check "a race on another service rebases and retries" test_race_without_conflict
check "a conflicting race re-applies the pin on the new head" test_race_with_conflict
check "five lost races fail loudly" test_retry_exhaustion
check "an invalid digest is rejected before any write" test_rejects_bad_digest
check "a missing pins file fails" test_missing_pins_file
check "pull-request mode pushes a branch and opens a PR" test_pull_request_mode

echo "passed=$PASSED failed=$FAILED"
[ "$FAILED" -eq 0 ]
