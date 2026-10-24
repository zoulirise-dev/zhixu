#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/ScrollStyle.swift Tests/ScrollStyleIntegration.swift -o .build/scroll-style-integration
.build/scroll-style-integration
