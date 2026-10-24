#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo '目前仅支持 Apple Silicon macOS 构建。' >&2; exit 1; }
VERSION=2.103.0
SHA256=54be566e9f614bea5de8021e95b9ad33dfee3b9d2ea120c9c294c00defaa5014
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 "https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_macOS_arm64.zip" -o "$TEMP_DIR/gh.zip"
printf '%s  %s\n' "$SHA256" "$TEMP_DIR/gh.zip" | shasum -a 256 -c -
unzip -q "$TEMP_DIR/gh.zip" -d "$TEMP_DIR/unpacked"
install -m 755 "$TEMP_DIR/unpacked/gh_${VERSION}_macOS_arm64/bin/gh" Vendor/GitHubCLI/gh
printf 'GitHub CLI %s 已准备好。\n' "$VERSION"
