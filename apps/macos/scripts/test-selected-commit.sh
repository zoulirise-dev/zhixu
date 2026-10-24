#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Zhixu/Localization.swift -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Tests/SelectedCommitIntegration.swift -o .build/selected-commit-integration
.build/selected-commit-integration -appLanguage zh-Hans
