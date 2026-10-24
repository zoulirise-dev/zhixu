#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Localization.swift Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Sources/Zhixu/EditorDocument.swift Sources/Zhixu/Theme.swift Sources/Zhixu/ScrollStyle.swift Sources/Zhixu/AppDialogs.swift Sources/Zhixu/Model.swift Tests/AuthReliabilityIntegration.swift -o .build/auth-reliability-integration
.build/auth-reliability-integration -appLanguage zh-Hans
