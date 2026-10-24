#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Zhixu/Localization.swift -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Sources/Zhixu/EditorDocument.swift Sources/Zhixu/Theme.swift Sources/Zhixu/ScrollStyle.swift Sources/Zhixu/AppDialogs.swift Sources/Zhixu/Model.swift Tests/DialogLayoutIntegration.swift -o .build/dialog-layout-integration
.build/dialog-layout-integration -appLanguage zh-Hans
