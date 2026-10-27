#!/bin/bash
# Developer ID release; credentials stay in the user's Keychain/environment.
set -euo pipefail
: "${ZHIXU_SIGN_IDENTITY:?Set Developer ID identity}"
: "${ZHIXU_NOTARY_PROFILE:?Set Keychain notary profile}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT/apps/flutter_prototype"
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
OUT="$ROOT/dist/release-$VERSION"
APP="$OUT/枝序.app"
LOG="$ROOT/证书资料/公证记录/flutter-$VERSION-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" "$LOG" "$ROOT/.build"
xcrun notarytool history --keychain-profile "$ZHIXU_NOTARY_PROFILE" --output-format json > /dev/null
flutter build macos --release
[[ ! -e "$APP" ]] || { echo "Release staging app already exists: $APP"; exit 1; }
ditto 'build/macos/Build/Products/Release/枝序.app' "$APP"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/GitHubCLI"
cp "$ROOT/apps/macos/Vendor/GitHubCLI/gh" "$APP/Contents/Helpers/gh"
cp "$ROOT/apps/macos/Vendor/GitHubCLI/"{LICENSE,VERSION} "$APP/Contents/Resources/GitHubCLI/"
/usr/libexec/PlistBuddy -c 'Set LSMinimumSystemVersion 14.0' "$APP/Contents/Info.plist"
# Keep this release explicitly Apple Silicon; do not claim untested Intel support.
python3 - "$APP" "$ZHIXU_SIGN_IDENTITY" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]); identity=sys.argv[2]
for p in app.rglob('*'):
 if not p.is_file() or p.is_symlink(): continue
 kind=subprocess.check_output(['file','-b',str(p)],text=True)
 if 'Mach-O' not in kind: continue
 arch=subprocess.check_output(['lipo','-archs',str(p)],text=True).strip().split()
 if 'arm64' not in arch: raise RuntimeError('Missing arm64: '+str(p))
 if len(arch)>1:
  tmp=p.with_name(p.name+'.arm64')
  subprocess.run(['lipo',str(p),'-thin','arm64','-output',str(tmp)],check=True)
  tmp.chmod(p.stat().st_mode);tmp.replace(p)
 subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--timestamp',str(p)],check=True)
for p in sorted(app.rglob('*.framework'),key=lambda p:len(p.parts),reverse=True):
 subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--timestamp',str(p)],check=True)
subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--timestamp',str(app)],check=True)
PY
codesign --verify --deep --strict "$APP"
# Launch the actual hardened executable against an isolated preferences directory.
python3 - "$APP/Contents/MacOS/枝序" <<'PY'
import os,sys,tempfile,subprocess,time
with tempfile.TemporaryDirectory(prefix='zhixu-release-smoke-') as home:
 with open('/tmp/zhixu-release-launch.log','w') as log:
  p=subprocess.Popen([sys.argv[1]],env={**os.environ,'HOME':home},stdout=log,stderr=log)
  try:
   time.sleep(8)
   if p.poll() is not None: raise RuntimeError('Signed app exited: '+str(p.returncode))
  finally:
   if p.poll() is None: p.terminate();p.wait(timeout=15)
print('PASS hardened application launch')
PY
ZIP="$ROOT/.build/Zhixu-$VERSION-notary.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize() {
  local file="$1" name="$2" id status
  xcrun notarytool submit "$file" --keychain-profile "$ZHIXU_NOTARY_PROFILE" --output-format json > "$LOG/$name-submission.json"
  id=$(plutil -extract id raw "$LOG/$name-submission.json")
  echo "Submitted $name: $id"
  xcrun notarytool wait "$id" --keychain-profile "$ZHIXU_NOTARY_PROFILE" --timeout 15m --output-format json > "$LOG/$name-status.json"
  xcrun notarytool log "$id" --keychain-profile "$ZHIXU_NOTARY_PROFILE" "$LOG/$name-log.json"
  status=$(plutil -extract status raw "$LOG/$name-status.json")
  [[ "$status" == Accepted ]] || { echo "Notarization failed: $LOG/$name-log.json"; exit 1; }
}
notarize "$ZIP" app-archive
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
syspolicy_check distribution "$APP"
TOOLS="$ROOT/.build/dmg-layout-tools"
if [[ ! -x "$TOOLS/bin/python3" ]]; then
  python3 -m venv "$TOOLS"
  "$TOOLS/bin/python3" -m pip install -r "$ROOT/apps/macos/scripts/dmg-requirements.txt"
fi
swift -module-cache-path "$ROOT/.build/module-cache" "$ROOT/apps/macos/scripts/dmg-background.swift" "$ROOT/.build/dmg-background.tiff"
DMG="$OUT/Zhixu-$VERSION-macOS-arm64.dmg"
"$TOOLS/bin/python3" -m dmgbuild -s "$ROOT/apps/flutter_prototype/tool/dmg-settings.py" -D "app=$APP" -D "background=$ROOT/.build/dmg-background.tiff" "枝序" "$DMG"
codesign --force --sign "$ZHIXU_SIGN_IDENTITY" --timestamp "$DMG"
hdiutil verify "$DMG"
notarize "$DMG" dmg
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Release complete: $DMG"
