#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Zhixu/Localization.swift -disable-sandbox -module-cache-path "$PWD/.build/module-cache" Sources/Zhixu/Accounts.swift Sources/Zhixu/Git.swift Sources/Zhixu/EditorDocument.swift Sources/Zhixu/Theme.swift Sources/Zhixu/ScrollStyle.swift Sources/Zhixu/AppDialogs.swift Sources/Zhixu/Model.swift Sources/Zhixu/Syntax.swift Sources/Zhixu/MarkdownPreview.swift Sources/Zhixu/CodeEditor.swift Sources/Zhixu/Completion.swift Sources/Zhixu/CompletionTextView.swift Tests/CompletionIntegration.swift -o .build/completion-integration
.build/completion-integration -appLanguage zh-Hans
