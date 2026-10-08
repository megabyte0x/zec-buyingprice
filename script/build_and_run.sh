#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in
    run|--verify|--debug|--logs|--telemetry|--stop) ;;
    *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--stop]" >&2; exit 2 ;;
esac
APP_NAME="ZECBuyingPrice"
BUNDLE_ID="app.zec.buyingprice"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
app_processes() {
    local candidate_pid candidate_arguments
    while IFS= read -r candidate_pid; do
        candidate_arguments="$(ps -p "$candidate_pid" -o args= 2>/dev/null || true)"
        if [[ "$candidate_arguments" == "$APP_EXECUTABLE" || "$candidate_arguments" == "$APP_EXECUTABLE "* ]]; then
            printf '%s\n' "$candidate_pid"
        fi
    done < <(pgrep -x "$APP_NAME" || true)
}
gui_is_running() {
    local candidate_pid candidate_arguments
    while IFS= read -r candidate_pid; do
        candidate_arguments="$(ps -p "$candidate_pid" -o args= 2>/dev/null || true)"
        if [[ "$candidate_arguments" != "$APP_EXECUTABLE" && "$candidate_arguments" != "$APP_EXECUTABLE "* ]]; then continue; fi
        case "$candidate_arguments" in
            *--wallet-worker*|*--vault-guard*) continue ;;
        esac
        return 0
    done < <(app_processes)
    return 1
}
while IFS= read -r app_pid; do
    app_arguments="$(ps -p "$app_pid" -o args= 2>/dev/null || true)"
    if [[ "$app_arguments" != "$APP_EXECUTABLE" && "$app_arguments" != "$APP_EXECUTABLE "* ]]; then continue; fi
    case "$app_arguments" in
        *--wallet-worker*|*--vault-guard*) continue ;;
    esac
    kill -TERM "$app_pid" 2>/dev/null || true
done < <(app_processes)
for ((cleanup_attempt = 0; cleanup_attempt < 150; cleanup_attempt++)); do
    if [[ -z "$(app_processes)" ]]; then break; fi
    sleep 0.1
done
if [[ -n "$(app_processes)" ]]; then
    echo "The app is still closing protected storage. Wait for cleanup and retry." >&2
    exit 1
fi
if [[ "$MODE" == "--stop" ]]; then exit 0; fi
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
<key>NSFaceIDUsageDescription</key><string>Authenticate to unlock your viewing-only wallet and start mainnet syncing.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_BUNDLE"
case "$MODE" in
run) /usr/bin/open -n "$APP_BUNDLE" ;;
--verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; gui_is_running ;;
--debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
--logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
*) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--stop]" >&2; exit 2 ;;
esac
