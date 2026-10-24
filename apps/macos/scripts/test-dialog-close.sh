#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Sources/Zhixu/Theme.swift Tests/DialogCloseIntegration.swift -o .build/dialog-close-integration
.build/dialog-close-integration
