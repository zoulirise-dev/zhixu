#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
REPO_ROOT="$(cd ../.. && pwd)"
if [[ ! -x Vendor/GitHubCLI/gh ]]; then
    echo "缺少 GitHub CLI：请先运行 bash scripts/bootstrap-gh.sh" >&2
    exit 1
fi
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Explicitly record the build SDK, distinct from the minimum supported OS.
swift build -c release --disable-sandbox -debug-info-format none --sdk "$SDK_PATH" \
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
APP="${ZHIXU_APP_OUTPUT:-$REPO_ROOT/dist/枝序.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Zhixu "$APP/Contents/MacOS/Zhixu"
cp "$REPO_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIconZ.icns"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/GitHubCLI"
cp Vendor/GitHubCLI/gh "$APP/Contents/Helpers/gh"
cp Vendor/GitHubCLI/LICENSE Vendor/GitHubCLI/VERSION "$APP/Contents/Resources/GitHubCLI/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Zhixu</string>
<key>CFBundleIdentifier</key><string>app.zhixu.git</string>
<key>CFBundleName</key><string>枝序</string>
<key>CFBundleDisplayName</key><string>枝序</string>
<key>CFBundleIconFile</key><string>AppIconZ.icns</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>18</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
printf '%s\n' '"CFBundleDisplayName" = "Zhixu";' '"CFBundleName" = "Zhixu";' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '%s\n' '"CFBundleDisplayName" = "枝序";' '"CFBundleName" = "枝序";' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
# Reuse a configured identity across builds so macOS can recognize application updates.
SIGNING_RECORD="$REPO_ROOT/.build/signing-identity"
mkdir -p "$(dirname "$SIGNING_RECORD")"
SIGNING_IDENTITY="${ZHIXU_SIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$SIGNING_RECORD" ]]; then
    SIGNING_IDENTITY="$(cat "$SIGNING_RECORD")"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_FLAGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGNING_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGNING_FLAGS[@]}" "$APP/Contents/Helpers/gh"
codesign "${SIGNING_FLAGS[@]}" "$APP"
# Refresh the bundle metadata after rebuilding at the same path. The Dock must
# use this bundled icon before launch and after exit, without a runtime override.
touch "$APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" && "${ZHIXU_SKIP_REGISTER:-0}" != "1" ]]; then
    "$LSREGISTER" -f "$APP" || printf '%s\n' '应用注册信息未刷新；下次通过 Finder 打开应用时会重新注册。'
fi
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    printf '%s' "$SIGNING_IDENTITY" > "$SIGNING_RECORD"
else
    printf '%s\n' '当前使用临时签名：重新构建可能需要重新授权。可用 ZHIXU_SIGN_IDENTITY 配置固定代码签名证书。'
fi
printf '已构建：%s\n' "$APP"
