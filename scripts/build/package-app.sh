#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="VibeBar"
BUNDLE_ID="com.vibebar.app"

# Determine version from git tag, fallback to "0.0.0-dev"
VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")}"
VERSION="${VERSION#v}"  # strip leading 'v'

echo "==> Building $APP_NAME $VERSION (universal binary)"

# Step 1: Build universal binary
echo "==> swift build -c release (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 \
    --package-path "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/.build/apple/Products/Release"

# Step 2: Create .app bundle structure
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

# Step 3: Copy binaries
cp "$BUILD_DIR/VibeBarApp" "$MACOS_DIR/VibeBarApp"
cp "$BUILD_DIR/vibebar-agent" "$MACOS_DIR/vibebar-agent"

echo "==> Binaries copied to $MACOS_DIR"

# Step 4: Generate Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VibeBarApp</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Info.plist generated"

# Step 5: Package as .dmg
DMG_NAME="${APP_NAME}-${VERSION}-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_STAGING="$DIST_DIR/.dmg-staging"

rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Stage .app and /Applications symlink for drag-to-install
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating $DMG_NAME"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo "==> DMG created at: $DMG_PATH"

# Step 6: Compute SHA-256
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$DIST_DIR/$DMG_NAME.sha256"
echo "==> SHA-256: $SHA256"

echo ""
echo "Done! Output:"
echo "  $DMG_PATH"
echo "  $DIST_DIR/$DMG_NAME.sha256"
