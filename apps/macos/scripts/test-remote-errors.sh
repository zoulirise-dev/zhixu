#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Tests/RemoteFailureIntegration.swift -o .build/remote-failure-integration
.build/remote-failure-integration -appLanguage zh-Hans
