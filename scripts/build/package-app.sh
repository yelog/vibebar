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
cp "$BUILD_DIR/vibebar" "$MACOS_DIR/vibebar"

echo "==> Binaries copied to $MACOS_DIR"

# Step 3b: Bundle plugins and resources into Resources
RESOURCES_DIR="$CONTENTS/Resources"
mkdir -p "$RESOURCES_DIR"
cp -R "$REPO_ROOT/plugins" "$RESOURCES_DIR/plugins"
echo "==> Plugins bundled to $RESOURCES_DIR/plugins"

COMPONENT_VERSIONS_SRC="$REPO_ROOT/component-versions.json"
if [ ! -f "$COMPONENT_VERSIONS_SRC" ]; then
    echo "component-versions.json not found: $COMPONENT_VERSIONS_SRC" >&2
    exit 1
fi
cp "$COMPONENT_VERSIONS_SRC" "$RESOURCES_DIR/component-versions.json"
echo "==> Component versions bundled to $RESOURCES_DIR/component-versions.json"

manifest_claude_version="$(grep -E '"claudePluginVersion"' "$COMPONENT_VERSIONS_SRC" | head -n 1 | sed -E 's/.*"claudePluginVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
manifest_opencode_version="$(grep -E '"opencodePluginVersion"' "$COMPONENT_VERSIONS_SRC" | head -n 1 | sed -E 's/.*"opencodePluginVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
claude_plugin_version="$(grep -E '"version"' "$REPO_ROOT/plugins/claude-vibebar-plugin/.claude-plugin/plugin.json" | head -n 1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
opencode_plugin_version="$(grep -E '"version"' "$REPO_ROOT/plugins/opencode-vibebar-plugin/package.json" | head -n 1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

if [ "$manifest_claude_version" != "$claude_plugin_version" ]; then
    echo "Version mismatch: claudePluginVersion=$manifest_claude_version, plugin.json=$claude_plugin_version" >&2
    exit 1
fi
if [ "$manifest_opencode_version" != "$opencode_plugin_version" ]; then
    echo "Version mismatch: opencodePluginVersion=$manifest_opencode_version, package.json=$opencode_plugin_version" >&2
    exit 1
fi
echo "==> Component version manifest validated"

# Step 3c: Copy app icon
ICON_SRC="$REPO_ROOT/Sources/VibeBarApp/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    echo "==> App icon copied to $RESOURCES_DIR/AppIcon.icns"
fi

# Step 3d: Generate build timestamp
date -u '+%Y-%m-%d %H:%M:%S UTC' > "$RESOURCES_DIR/build-timestamp.txt"
echo "==> Build timestamp written to $RESOURCES_DIR/build-timestamp.txt"

# Step 3e: Embed Sparkle framework
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Find Sparkle framework from artifacts
SPARKLE_FRAMEWORK="$REPO_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    echo "==> Sparkle.framework embedded to $FRAMEWORKS_DIR"

    # Sign the Sparkle framework (ad-hoc only for local builds)
    # CI builds will be properly signed by codesign-and-notarize.sh
    if [ "${CODESIGN_ENABLED:-}" != "1" ]; then
        codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework"
        echo "==> Sparkle.framework signed (ad-hoc)"
    else
        echo "==> Skipping ad-hoc signing of Sparkle (will be signed with Developer ID)"
    fi

    # Update rpath to find the framework
    install_name_tool -delete_rpath "@executable_path/../lib" "$MACOS_DIR/VibeBarApp" 2>/dev/null || true
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/VibeBarApp"
    echo "==> Updated rpath for Sparkle.framework"
else
    echo "Warning: Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2
fi

# Step 4: Generate Info.plist
# Generate numeric bundle version for Sparkle (e.g., 1.3.0-beta.4 -> 13004)
BUNDLE_VERSION=$(echo "$VERSION" | sed -E 's/([0-9]+)\.([0-9]+)\.([0-9]+).*/\1\2\3/; s/^0*//')
# Add beta/alpha/rc number (e.g., beta.4 -> 4)
if [[ "$VERSION" =~ -(beta|alpha|rc)\.?([0-9]+) ]]; then
    PRERELEASE_NUM="${BASH_REMATCH[2]:-0}"
    BUNDLE_VERSION="${BUNDLE_VERSION}$(printf "%02d" "$PRERELEASE_NUM")"
fi
# Ensure it's a valid version number (default to 1 if empty)
BUNDLE_VERSION=${BUNDLE_VERSION:-1}

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
    <string>${BUNDLE_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <!-- Sparkle Updater Configuration -->
    <!-- SUFeedURL is intentionally omitted - Sparkle uses delegate method feedURLString(for:) -->
    <key>SUPublicEDKey</key>
    <string>OJo/oEqSjtmok1HYx+XgFHLq1FkUAJs8hsDms0+Uv98=</string>
</dict>
</plist>
PLIST
echo "==> Info.plist generated with CFBundleVersion=${BUNDLE_VERSION}"

echo "==> Info.plist generated"

# Step 5: Ad-hoc sign bundle for local distribution.
# This binds Info.plist/resources into the app signature and keeps
# a stable bundle identifier for TCC features such as notifications.
echo "==> Ad-hoc signing app bundle"
codesign --force --deep \
    --sign - \
    --timestamp=none \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR"
echo "==> Ad-hoc signing complete"

# Step 6: Code sign the .app bundle (CI only, must happen BEFORE creating DMG)
if [ "${CODESIGN_ENABLED:-}" = "1" ]; then
    echo "==> Running code signing on .app bundle..."
    bash "$SCRIPT_DIR/codesign-and-notarize.sh" sign "$APP_DIR"
else
    echo "==> Skipping code signing (set CODESIGN_ENABLED=1 to enable)"
fi

# Step 7: Package as .dmg (from the signed .app)
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

# Step 8: Sign DMG and notarize (CI only)
if [ "${CODESIGN_ENABLED:-}" = "1" ]; then
    echo "==> Signing DMG and submitting for notarization..."
    bash "$SCRIPT_DIR/codesign-and-notarize.sh" notarize "$DMG_PATH"
fi

# Step 9: Compute SHA-256 (must be after signing, since stapler modifies the DMG)
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$DIST_DIR/$DMG_NAME.sha256"
echo "==> SHA-256: $SHA256"

echo ""
echo "Done! Output:"
echo "  $DMG_PATH"
echo "  $DIST_DIR/$DMG_NAME.sha256"
