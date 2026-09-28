#!/usr/bin/env bash
# Install mikefarah/yq at a pinned version, verified by SHA-256, when the runner
# does not already have a v4 yq. Checksums are the SHA-256 column of the release's
# `checksums` file for this version; bump version and both sums together.
set -euo pipefail

YQ_VERSION="v4.53.6"
declare -A YQ_SHA256=(
  [amd64]="c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385"
  [arm64]="88a1016bc1d657375a35864e4f44b6f333df8ff97b559f51bba0adcb2169df09"
)

if command -v yq >/dev/null && yq --version 2>/dev/null | grep -q 'mikefarah.* v4\.'; then
  echo "yq present: $(yq --version)"
  exit 0
fi

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "::error::unsupported architecture $(uname -m)"; exit 1 ;;
esac

dest="${RUNNER_TEMP:-/tmp}/yq-bin"
mkdir -p "$dest"
curl -fsSL --retry 3 -o "$dest/yq" \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}"
echo "${YQ_SHA256[$arch]}  $dest/yq" | sha256sum -c --quiet -
chmod +x "$dest/yq"
echo "$dest" >> "$GITHUB_PATH"
echo "installed yq ${YQ_VERSION} (${arch})"
