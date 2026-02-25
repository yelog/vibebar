#!/usr/bin/env bash
set -euo pipefail

# ─── Input parameters ───
APP_DIR="${1:?Usage: $0 <path-to-app> <path-to-dmg>}"
DMG_PATH="${2:?Usage: $0 <path-to-app> <path-to-dmg>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENTITLEMENTS="$REPO_ROOT/Sources/VibeBarApp/Resources/VibeBar.entitlements"

# ─── Environment variables (injected by CI) ───
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

SIGNING_IDENTITY="Developer ID Application: ${APPLE_TEAM_ID}"

echo "==> Signing identity: $SIGNING_IDENTITY"

# ─── Step 1: Sign helper binaries (inside-out order) ───
echo "==> Signing helper binary: vibebar-agent"
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_DIR/Contents/MacOS/vibebar-agent"

# ─── Step 2: Sign the main app bundle ───
echo "==> Signing main app bundle"
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_DIR"

# ─── Step 3: Verify signature ───
echo "==> Verifying signature..."
codesign --verify --verbose=2 "$APP_DIR"

echo "==> Checking Gatekeeper assessment..."
spctl --assess --type execute --verbose=2 "$APP_DIR" || true

# ─── Step 4: Sign the DMG ───
echo "==> Signing DMG"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

# ─── Step 5: Submit for notarization ───
echo "==> Submitting for notarization (this may take several minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --timeout 30m

# ─── Step 6: Staple notarization ticket ───
echo "==> Stapling notarization ticket to DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Code signing and notarization complete!"
