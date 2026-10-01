#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="ZECBuyingPrice"
BUNDLE_ID="app.zec.buyingprice"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
BIN_DIR="$(swift build --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Sources/ZECBuyingPrice/Resources/LabIcon.icns" "$APP_BUNDLE/Contents/Resources/LabIcon.icns"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP_BUNDLE/Contents/Resources/" \;
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP_BUNDLE/Contents/MacOS/" \;
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>ZEC Buying Price</string>
<key>CFBundleIconFile</key><string>LabIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_BUNDLE"
case "$MODE" in
run) /usr/bin/open -n "$APP_BUNDLE" ;;
--verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
--debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
--logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
*) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
