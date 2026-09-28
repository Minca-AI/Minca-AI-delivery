#!/usr/bin/env bash
# Decide what image.yml builds and whether it pushes. Writes image, tag and push
# to GITHUB_OUTPUT.
#
# Env: POOL, PUSH_INPUT (true|false), IMAGE_NAME, EVENT, REGISTRY, ROLE_ARN, GITHUB_REPOSITORY, GITHUB_SHA.
set -euo pipefail

case "$POOL" in
  ci|large) ;;
  *) echo "::error::pool must be 'ci' or 'large' (got '$POOL')"; exit 1 ;;
esac

# A pull request never pushes, whatever the caller passes: it builds and
# smoke-tests only, so a fork can never publish an image (design 6.2).
case "$EVENT" in
  pull_request|pull_request_target) push=false ;;
  *) push="$PUSH_INPUT" ;;
esac
[ "$push" = true ] || [ "$push" = false ] || { echo "::error::push must be true or false"; exit 1; }

name="${IMAGE_NAME:-${GITHUB_REPOSITORY#*/}}"
name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
if ! [[ "$name" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "::error::'$name' is not a valid ECR repository name"; exit 1
fi

if [ "$push" = true ] && { [ -z "$REGISTRY" ] || [ -z "$ROLE_ARN" ]; }; then
  echo "::error::push needs the variables DELIVERY_ECR_REGISTRY and DELIVERY_ECR_ROLE_ARN (see README, Onboarding)"
  exit 1
fi

# Without a registry (a fork, or this repository's self-test) the image still gets
# a well-formed local name so the build and smoke test run identically.
image="${REGISTRY:-local}/minca/${name}"
{
  echo "image=$image"
  echo "tag=sha-${GITHUB_SHA}"
  echo "push=$push"
} >> "$GITHUB_OUTPUT"
echo "image=$image tag=sha-${GITHUB_SHA} push=$push"
