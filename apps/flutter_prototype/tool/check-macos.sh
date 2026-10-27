#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze
flutter test
flutter build macos --release
app="build/macos/Build/Products/Release/枝序.app"
helper="../macos/Vendor/GitHubCLI/gh"
if [ -f "$helper" ]; then
  mkdir -p "$app/Contents/Helpers"
  cp "$helper" "$app/Contents/Helpers/gh"
  mkdir -p "$app/Contents/Resources/GitHubCLI"
  cp ../macos/Vendor/GitHubCLI/LICENSE ../macos/Vendor/GitHubCLI/VERSION "$app/Contents/Resources/GitHubCLI/"
  codesign --force --deep --sign - "$app"
fi
printf '%s\n' '原型位于 build/macos/Build/Products/Release/枝序.app'
