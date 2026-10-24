#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Tests/AccountIntegration.swift -o .build/account-integration
.build/account-integration
