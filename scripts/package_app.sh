#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexScreenshotBridge"
PRODUCT_NAME="${PRODUCT_NAME:-$APP_NAME}"
BUNDLE_ID="${BUNDLE_ID:-com.spirosraptis.CodexScreenshotBridge}"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="${MIN_MACOS:-13.0}"
OUTPUT_APP="${OUTPUT_APP:-$HOME/Applications/${APP_NAME}.app}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Building release binary..."
(
  cd "$REPO_ROOT"
  swift build -c release
)

BIN_SRC="$(find "$REPO_ROOT/.build" -type f -path "*/release/${APP_NAME}" | head -n 1)"

if [[ ! -x "$BIN_SRC" ]]; then
  echo "Release binary not found in .build/*/release/${APP_NAME}" >&2
  exit 1
fi

echo "Packaging app at: $OUTPUT_APP"
rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS" "$OUTPUT_APP/Contents/Resources"

cp "$BIN_SRC" "$OUTPUT_APP/Contents/MacOS/$APP_NAME"
chmod +x "$OUTPUT_APP/Contents/MacOS/$APP_NAME"

cat > "$OUTPUT_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing app (ad-hoc)..."
codesign --force --deep --sign - "$OUTPUT_APP"

echo "Done."
echo "App: $OUTPUT_APP"
echo "Launch with: open \"$OUTPUT_APP\""
