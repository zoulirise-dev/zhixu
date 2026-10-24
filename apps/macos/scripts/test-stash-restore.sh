#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Zhixu/Localization.swift -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Tests/StashRestoreIntegration.swift -o .build/stash-restore-integration
.build/stash-restore-integration -appLanguage zh-Hans
