#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Zhixu/Localization.swift -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Sources/Zhixu/EditorDocument.swift Sources/Zhixu/Theme.swift Sources/Zhixu/Syntax.swift Sources/Zhixu/Completion.swift Sources/Zhixu/CompletionTextView.swift Sources/Zhixu/CodeEditor.swift Sources/Zhixu/RestoreSplitEditor.swift Tests/SplitComparisonIntegration.swift -o .build/split-comparison-integration
.build/split-comparison-integration -appLanguage zh-Hans
