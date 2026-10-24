#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Tests/SettingsRemoteIntegration.swift -o .build/settings-remote-integration
.build/settings-remote-integration
