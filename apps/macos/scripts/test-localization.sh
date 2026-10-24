#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Tests/LocalizationIntegration.swift -o .build/localization-integration
.build/localization-integration
