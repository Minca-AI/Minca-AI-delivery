#!/usr/bin/env bash
# Validates build-smoke-push's build-args input before anything is built.
# BUILD_ARGS holds newline-separated NAME=value lines (docker/build-push-action's format).
# Fail closed: every faulty line is reported, by line number, and the script exits 1.
# A value is never printed: build args are recorded in the image history, and a value
# pasted by mistake must not reach a public Actions log as well. Rules: README "Build args".
set -euo pipefail

NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'
CREDENTIAL_WORDS=(TOKEN SECRET PASSWORD PASSWD CREDENTIAL PRIVATE APIKEY API_KEY ACCESS_KEY)
faults=0
names=()
declare -A seen=()

fault() { echo "::error::build-args line $1: $2"; faults=$((faults + 1)); }

credential_like() { # <NAME upper-cased> -> 0 when it contains a credential word
  local word
  for word in "${CREDENTIAL_WORDS[@]}"; do [[ "$1" == *"$word"* ]] && return 0; done
  return 1
}

check_value() { # <n> <name> <value>
  # build-push-action CSV-parses and trims the list: such a value would be rewritten.
  if [[ "$3" == *'"'* || "$3" =~ ^[[:space:]] || "$3" =~ [[:space:]]$ ]]; then
    fault "$1" "$2: the value has a double quote or leading/trailing whitespace, which the build action would rewrite"
    return 1
  fi
}

check_line() { # <n> <line, CR already stripped>
  local n="$1" line="$2" name upper
  if [[ "$line" != *=* ]]; then fault "$n" "not a NAME=value line"; return; fi
  name="${line%%=*}"
  if ! [[ "$name" =~ $NAME_RE ]]; then fault "$n" "the name must match [A-Za-z_][A-Za-z0-9_]*"; return; fi
  upper="${name^^}"
  if [[ "$upper" == BUILDKIT_* ]]; then fault "$n" "$name: BUILDKIT_* arguments change how the image is built; not accepted"; return; fi
  if credential_like "$upper"; then fault "$n" "$name reads like a credential; build args are recorded in the image history"; return; fi
  if [[ -n "${seen[$name]:-}" ]]; then fault "$n" "$name: duplicate of line ${seen[$name]}"; return; fi
  check_value "$n" "$name" "${line#*=}" || return 0
  seen[$name]="$n"; names+=("$name")
}

main() {
  local n=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1)); line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    check_line "$n" "$line"
  done <<<"${BUILD_ARGS:-}"
  if ((faults > 0)); then echo "build-args: $faults fault(s), refusing to build"; exit 1; fi
  if ((${#names[@]} == 0)); then echo "build-args: none"; else echo "build-args: ${names[*]}"; fi
}

main
