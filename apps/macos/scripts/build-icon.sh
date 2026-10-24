#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$PWD/.build/module-cache" scripts/make-icon.swift -o .build/make-icon
.build/make-icon .build/Zhixu.iconset
# Use Apple's encoder: small icns chunks and Retina representations must be encoded correctly.
iconutil -c icns .build/Zhixu.iconset -o Assets/AppIcon.icns
cp .build/Zhixu.iconset/icon_512x512@2x.png ../../assets/brand/AppIcon.png
