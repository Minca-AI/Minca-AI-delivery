#!/usr/bin/env bash
# ECR side of promote.yml.
#
#   promote-ecr.sh verify     the tag exists and resolves to the expected digest,
#                             so a pin can never name a missing or different image
#   promote-ecr.sh move-live  point <client>-<env>-live at that digest, so the
#                             lifecycle policy never expires a running image
#
# Env: REPOSITORY (ECR repository name, e.g. minca/gnp-codifier), TAG, DIGEST,
#      LIVE_TAG (move-live only). AWS credentials come from ecr-login.
set -euo pipefail

verify() {
  local actual
  if ! actual="$(aws ecr describe-images --repository-name "$REPOSITORY" \
      --image-ids "imageTag=$TAG" --query 'imageDetails[0].imageDigest' --output text 2>&1)"; then
    echo "::error::$REPOSITORY:$TAG not found in ECR: $actual"; exit 1
  fi
  if [ "$actual" != "$DIGEST" ]; then
    echo "::error::$REPOSITORY:$TAG is $actual in ECR, not the promoted $DIGEST"; exit 1
  fi
  echo "verified $REPOSITORY:$TAG = $DIGEST"
}

move_live() {
  local manifest media output
  manifest="$(aws ecr batch-get-image --repository-name "$REPOSITORY" \
    --image-ids "imageDigest=$DIGEST" --query 'images[0].imageManifest' --output text)"
  media="$(aws ecr batch-get-image --repository-name "$REPOSITORY" \
    --image-ids "imageDigest=$DIGEST" --query 'images[0].imageManifestMediaType' --output text)"
  if output="$(aws ecr put-image --repository-name "$REPOSITORY" --image-tag "$LIVE_TAG" \
      --image-manifest "$manifest" --image-manifest-media-type "$media" 2>&1)"; then
    echo "moved $LIVE_TAG to $DIGEST"
  elif grep -q ImageAlreadyExistsException <<<"$output"; then
    # Same digest already carries the live tag: a re-promotion, nothing to move.
    echo "$LIVE_TAG already points at $DIGEST"
  else
    echo "::error::could not move $LIVE_TAG: $output"; exit 1
  fi
}

case "${1:-}" in
  verify) verify ;;
  move-live) move_live ;;
  *) echo "usage: $0 verify|move-live" >&2; exit 2 ;;
esac
