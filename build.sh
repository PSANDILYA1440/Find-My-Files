
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Find My Files"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"

mkdir -p "$BUILD_DIR"

case "$TARGET_ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported TARGET_ARCH: $TARGET_ARCH (expected arm64 or x86_64)." >&2
        exit 1
        ;;
esac

if [[ -n "${PREBUILT_BINARY:-}" ]]; then
    if [[ ! -f "$PREBUILT_BINARY" ]]; then
        echo "PREBUILT_BINARY does not point to a file: $PREBUILT_BINARY" >&2
        exit 1
    fi
    cp "$PREBUILT_BINARY" "$BUILD_DIR/FindMyFiles"
else
    swiftc \
        -sdk "$SDK_PATH" \
        -target "$TARGET_ARCH-apple-macosx15.0" \
        "$PROJECT_DIR/run.swift" \
        -o "$BUILD_DIR/FindMyFiles"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/WebUI"

cp "$BUILD_DIR/FindMyFiles" "$APP_BUNDLE/Contents/MacOS/FindMyFiles"
cp -R "$PROJECT_DIR/WebUI/." "$APP_BUNDLE/Contents/Resources/WebUI/"
sips -s format png "$PROJECT_DIR/Assets.xcassets/Find My Files icon_512x512.icns" \
    --out "$APP_BUNDLE/Contents/Resources/WebUI/brand-icon.png" >/dev/null
xattr -c "$APP_BUNDLE/Contents/Resources/WebUI/brand-icon.png"
cp "$PROJECT_DIR/Assets.xcassets/Find My Files icon_512x512.icns" \
    "$APP_BUNDLE/Contents/Resources/FindMyFiles.icns"
xattr -c "$APP_BUNDLE/Contents/Resources/FindMyFiles.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FindMyFiles</string>
    <key>CFBundleIdentifier</key>
    <string>com.findmyfiles.app</string>
    <key>CFBundleName</key>
    <string>Find My Files</string>
    <key>CFBundleIconFile</key>
    <string>FindMyFiles.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --identifier com.findmyfiles.app "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
echo "Launch with: open \"$APP_BUNDLE\""
