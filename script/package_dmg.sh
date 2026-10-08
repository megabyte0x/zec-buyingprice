#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Yash Garg (9UR77TD484)}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/ZECBuyingPrice.app"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
mkdir -p "$ROOT_DIR/dist"
STAGING_DIR=$(mktemp -d "$ROOT_DIR/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
RELEASE_APP="$STAGING_DIR/ZECBuyingPrice.app"
mkdir -p "$RELEASE_APP/Contents/MacOS" "$RELEASE_APP/Contents/Resources"
cp "$BIN_DIR/ZECBuyingPrice" "$RELEASE_APP/Contents/MacOS/"
cp "$ROOT_DIR/Sources/ZECBuyingPrice/Resources/LabIcon.icns" "$RELEASE_APP/Contents/Resources/"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$RELEASE_APP/Contents/Resources/" \;
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$RELEASE_APP/Contents/MacOS/" \;
cat > "$RELEASE_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ZECBuyingPrice</string>
<key>CFBundleIdentifier</key><string>app.zec.buyingprice</string>
<key>CFBundleName</key><string>ZEC Buying Price</string>
<key>CFBundleIconFile</key><string>LabIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSFaceIDUsageDescription</key><string>Authenticate to unlock your viewing-only wallet and start mainnet syncing.</string>
</dict></plist>
PLIST
ln -s /Applications "$STAGING_DIR/Applications"
TOOLCHAIN_DIR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
COMPAT_LIBRARY="$TOOLCHAIN_DIR/usr/lib/swift-6.2/macosx/libswiftCompatibilitySpan.dylib"
if otool -L "$RELEASE_APP/Contents/MacOS/ZECBuyingPrice" | rg -q libswiftCompatibilitySpan; then
  test -f "$COMPAT_LIBRARY"
  cp "$COMPAT_LIBRARY" "$STAGING_DIR/ZECBuyingPrice.app/Contents/MacOS/"
fi
while IFS= read -r -d '' LIBRARY; do
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$LIBRARY"
done < <(find "$RELEASE_APP" -name '*.dylib' -print0)
while IFS= read -r -d '' BUNDLE; do
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$BUNDLE"
done < <(find "$RELEASE_APP" -depth -name '*.bundle' -print0)
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$RELEASE_APP"
codesign --verify --deep --strict --verbose=2 "$RELEASE_APP"
"$ROOT_DIR/script/build_and_run.sh" --stop
rm -rf "$APP_BUNDLE"
ditto "$RELEASE_APP" "$APP_BUNDLE"
DMG_PATH="$ROOT_DIR/dist/ZECBuyingPrice-$VERSION-arm64.dmg"
hdiutil create -volname 'ZEC Buying Price' -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi
cd "$ROOT_DIR/dist"
shasum -a 256 "$(basename "$DMG_PATH")" > SHA256SUMS.txt
