#!/usr/bin/env bash
# Install a pinned, checksum-verified linux-amd64 tool tarball for the self-test.
# Usage: install-tool.sh <name> <url> <sha256>
# The binary <name> is extracted onto a directory added to GITHUB_PATH.
set -euo pipefail

name="$1" url="$2" sha256="$3"
dest="${RUNNER_TEMP:-/tmp}/tools"
mkdir -p "$dest"
curl -fsSL --retry 3 -o "$dest/$name.tar.gz" "$url"
echo "$sha256  $dest/$name.tar.gz" | sha256sum -c --quiet -
tar -xzf "$dest/$name.tar.gz" -C "$dest" "$name"
rm -f "$dest/$name.tar.gz"
echo "$dest" >> "$GITHUB_PATH"
echo "installed $name from $url"
