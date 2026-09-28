#!/usr/bin/env bash
# bump-pin.sh -- write one service's tag and digest into a deploy repo's pins.yaml
# and land it, either as a direct commit (dev) or as a pull request (prod).
#
# Inputs are environment variables (the action maps its inputs onto them):
#   REMOTE        git URL or local path of the deploy repository
#   BASE_BRANCH   branch that holds the pins (default main)
#   PINS_PATH     path of pins.yaml inside the repository
#   SERVICE       key under `services:` (lowercase, digits, dashes)
#   IMAGE         optional; written to services.<service>.image when non-empty
#   TAG           image tag, e.g. sha-<40 hex>
#   DIGEST        sha256:<64 hex>
#   ENVIRONMENT   environment name, used in the commit message and PR branch
#   MODE          commit | pull-request
#   GH_TOKEN      optional; HTTPS auth for github.com and the gh CLI (PR mode)
#   MAX_ATTEMPTS  push attempts before failing (default 5)
#
# Concurrency: two promotions can race on the same branch. A rejected push is
# rebased onto the new head and retried; when the rebase conflicts (both touched
# the same lines) the edit is re-applied on the fresh head instead, because the
# edit is idempotent and the fresh head is the only state worth building on.
set -euo pipefail

BASE_BRANCH="${BASE_BRANCH:-main}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
BACKOFF_SECONDS="${BACKOFF_SECONDS:-3}"
GIT_USER_NAME="${GIT_USER_NAME:-minca-delivery[bot]}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-minca-delivery-bot@users.noreply.github.com}"

die() { echo "::error::bump-pin: $*" >&2; exit 1; }
log() { echo "bump-pin: $*"; }

validate_inputs() {
  local name
  for name in REMOTE PINS_PATH SERVICE TAG DIGEST ENVIRONMENT MODE; do
    [ -n "${!name:-}" ] || die "$name is required"
  done
  [[ "$SERVICE" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "invalid service '$SERVICE'"
  [[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "invalid tag '$TAG'"
  [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || die "invalid digest '$DIGEST'"
  [[ "$ENVIRONMENT" =~ ^[a-z0-9-]+$ ]] || die "invalid environment '$ENVIRONMENT'"
  case "$MODE" in commit|pull-request) ;; *) die "mode must be commit or pull-request" ;; esac
  command -v yq >/dev/null || die "yq is required on PATH"
}

# Authenticate through an HTTP header rather than a URL-embedded token, so the
# token never appears in a remote URL, `git remote -v`, or an error message.
git_cmd() {
  if [ -n "${GH_TOKEN:-}" ]; then
    local basic
    basic="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}" "$@"
  else
    git "$@"
  fi
}

clone_repo() {
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  git_cmd clone --quiet --branch "$BASE_BRANCH" "$REMOTE" "$WORKDIR/repo"
  cd "$WORKDIR/repo"
  git config user.name "$GIT_USER_NAME"
  git config user.email "$GIT_USER_EMAIL"
  [ -f "$PINS_PATH" ] || die "$PINS_PATH does not exist on $BASE_BRANCH; the deploy repo owns its environments"
}

# Returns 0 when the file changed, 1 when the pin was already in place.
# Called in conditionals, where `set -e` is suspended, so every command that can
# fail is checked explicitly: a failed edit must never read as "already pinned".
apply_pin() {
  export SERVICE TAG DIGEST IMAGE="${IMAGE:-}"
  yq -i '.services[strenv(SERVICE)].tag = strenv(TAG) | .services[strenv(SERVICE)].digest = strenv(DIGEST)' \
    "$PINS_PATH" || die "could not edit $PINS_PATH"
  if [ -n "$IMAGE" ]; then
    yq -i '.services[strenv(SERVICE)].image = strenv(IMAGE)' "$PINS_PATH" || die "could not edit $PINS_PATH"
  fi
  ! git diff --quiet -- "$PINS_PATH"
}

commit_pin() {
  git add -- "$PINS_PATH"
  git commit --quiet -m "chore(pins): ${SERVICE} ${TAG} [${ENVIRONMENT}]"
}

# Test seam: tests/bump-pin/ uses it to push a competing commit between our
# commit and our push. Unset in the action, so it never runs in CI or prod.
before_push() {
  if [ -n "${BUMP_PIN_BEFORE_PUSH:-}" ]; then
    ATTEMPT="$1" bash -c "$BUMP_PIN_BEFORE_PUSH"
  fi
}

# Bring the local commit on top of the new remote head. Sets UPSTREAM_HAS_PIN=1
# when upstream already carries this exact pin, leaving nothing to push. Not
# called in a conditional, so `set -e` still stops it on a failed fetch.
restack_on_remote() {
  UPSTREAM_HAS_PIN=0
  git_cmd fetch --quiet origin "$BASE_BRANCH"
  if git rebase --quiet "origin/$BASE_BRANCH" >/dev/null 2>&1; then
    return 0
  fi
  log "rebase conflicted; re-applying the pin on the new head"
  git rebase --abort
  git reset --quiet --hard "origin/$BASE_BRANCH"
  if apply_pin; then
    commit_pin
  else
    UPSTREAM_HAS_PIN=1
  fi
}

land_commit() {
  local attempt output
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    before_push "$attempt"
    if output="$(git_cmd push --quiet origin "HEAD:${BASE_BRANCH}" 2>&1)"; then
      log "pinned ${SERVICE} ${TAG} on ${BASE_BRANCH} (attempt ${attempt})"
      return 0
    fi
    # Printed so a rejection that is not a race (auth, branch protection) is
    # visible instead of looking like five lost races.
    log "push rejected (attempt ${attempt}/${MAX_ATTEMPTS}): ${output}"
    restack_on_remote
    if [ "$UPSTREAM_HAS_PIN" = 1 ]; then
      log "upstream already pins ${SERVICE} ${TAG}"
      return 0
    fi
    sleep $(( attempt * BACKOFF_SECONDS ))
  done
  die "gave up after ${MAX_ATTEMPTS} attempts racing other promotions on ${BASE_BRANCH}"
}

land_pull_request() {
  local branch="pins/${ENVIRONMENT}/${SERVICE}/${TAG}"
  git checkout --quiet -b "$branch"
  commit_pin
  # Force: re-promoting the same tag rewrites only this bot-owned branch.
  git_cmd push --quiet --force origin "HEAD:refs/heads/${branch}"
  if [ -n "$(gh pr list --repo "$GH_REPO" --head "$branch" --state open --json number --jq '.[].number')" ]; then
    log "pull request for ${branch} already open"
    return 0
  fi
  gh pr create --repo "$GH_REPO" --base "$BASE_BRANCH" --head "$branch" \
    --title "chore(pins): ${SERVICE} ${TAG} [${ENVIRONMENT}]" \
    --body "Promotes \`${SERVICE}\` to \`${TAG}\` (\`${DIGEST}\`) in \`${ENVIRONMENT}\`. Opened by the promote workflow."
}

main() {
  validate_inputs
  clone_repo
  if ! apply_pin; then
    log "${SERVICE} is already pinned to ${TAG} in ${PINS_PATH}; nothing to do"
    return 0
  fi
  if [ "$MODE" = "commit" ]; then
    commit_pin
    land_commit
  else
    [ -n "${GH_REPO:-}" ] || die "GH_REPO (owner/name) is required in pull-request mode"
    land_pull_request
  fi
}

main "$@"
