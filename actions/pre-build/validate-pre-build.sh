#!/usr/bin/env bash
# Validates the pre-build action's inputs before anything runs, and decides whether the optional
# AWS session is assumed. Fail closed: every fault is reported and the script exits 1.
#
# Env: SCRIPT (path relative to WORKDIR), ROLE_ARN, WORKDIR (the checkout directory the script runs
#      in), EVENT (github.event_name), GITHUB_OUTPUT.
# Writes to GITHUB_OUTPUT: run (true|false), assume (true|false).
#
# Rules (README "Pre-build"):
#   - no script: nothing to do, and a role without a script is a mistake (a credential nobody uses);
#   - the script is a relative path of plain characters, no `..`, no leading `-` or `/`, that names a
#     regular file which, once symlinks are resolved, still lives inside WORKDIR;
#   - the role is an IAM role ARN;
#   - the session is assumed only on an allow-list of events whose code and token belong to the
#     repository itself (push, workflow_dispatch, schedule, release). Every other event (a pull
#     request, workflow_run, issue_comment, merge_group, repository_dispatch, ...) runs the script
#     WITHOUT credentials, and the script decides for itself what that means (a build that needs
#     them must degrade explicitly on those events and fail on the others);
#   - WORKDIR has no `..` segment.
set -euo pipefail

SCRIPT="${SCRIPT:-}"
ROLE_ARN="${ROLE_ARN:-}"
WORKDIR="${WORKDIR:-.}"
EVENT="${EVENT:-}"

faults=0
fault() { echo "::error::pre-build: $1"; faults=$((faults + 1)); }

write_outputs() { # <run> <assume>
  echo "run=$1" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "assume=$2" >> "${GITHUB_OUTPUT:-/dev/null}"
}

check_workdir() {
  local seg
  IFS='/' read -r -a wsegments <<<"$WORKDIR"
  for seg in "${wsegments[@]}"; do
    if [[ "$seg" == ".." ]]; then fault "working-directory must not contain '..' segments"; return; fi
  done
}

check_script() {
  local rel="$SCRIPT" seg resolved root
  if ! [[ "$rel" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*$ ]]; then
    fault "script must be a relative path of letters, digits, '_', '.', '-' and '/', not starting with '-' or '/'"
    return
  fi
  IFS='/' read -r -a segments <<<"$rel"
  for seg in "${segments[@]}"; do
    if [[ -z "$seg" || "$seg" == "." || "$seg" == ".." ]]; then
      fault "script path must not contain empty, '.' or '..' segments"
      return
    fi
  done
  if [[ ! -f "$WORKDIR/$rel" ]]; then
    fault "script '$rel' is not a regular file under the working directory"
    return
  fi
  resolved="$(realpath -- "$WORKDIR/$rel")"
  root="$(realpath -- "$WORKDIR")"
  if [[ "$resolved" != "$root"/* ]]; then
    fault "script '$rel' resolves outside the working directory"
  fi
}

check_role() {
  # An IAM role ARN: partition, 12-digit account, path and name of allowed characters.
  if ! [[ "$ROLE_ARN" =~ ^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,255}$ ]] || [[ "$ROLE_ARN" == *..* ]]; then
    fault "pre-build-role-arn is not an IAM role ARN"
  fi
}

main() {
  if [[ -z "$SCRIPT" ]]; then
    [[ -z "$ROLE_ARN" ]] || fault "pre-build-role-arn is set but pre-build is empty"
    if ((faults > 0)); then echo "pre-build: refusing to build"; exit 1; fi
    echo "pre-build: none"
    write_outputs false false
    return
  fi
  check_workdir
  check_script
  [[ -z "$ROLE_ARN" ]] || check_role
  if ((faults > 0)); then echo "pre-build: $faults fault(s), refusing to build"; exit 1; fi

  local assume=false
  if [[ -n "$ROLE_ARN" ]]; then
    case "$EVENT" in
      push|workflow_dispatch|schedule|release) assume=true ;;
      *) echo "pre-build: a $EVENT run never gets AWS credentials: the script runs WITHOUT them" ;;
    esac
  fi
  echo "pre-build: $SCRIPT (aws session: $assume)"
  write_outputs true "$assume"
}

main
