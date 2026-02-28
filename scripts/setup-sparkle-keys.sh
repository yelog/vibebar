#!/usr/bin/env bash
# Setup script for Sparkle EdDSA signing keys
# Run this locally to generate keys and set up GitHub secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Sparkle EdDSA Key Setup"
echo "=========================================="
echo ""

# Check if Sparkle's generate_keys tool is available
if ! command -v generate_keys &> /dev/null; then
    echo "Downloading Sparkle tools..."
    SPARKLE_VERSION="2.6.4"
    TEMP_DIR=$(mktemp -d)
    curl -L -o "$TEMP_DIR/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar -xf "$TEMP_DIR/Sparkle.tar.xz" -C "$TEMP_DIR"
    GENERATE_KEYS="$TEMP_DIR/bin/generate_keys"
else
    GENERATE_KEYS="generate_keys"
fi

# Generate keys
echo "Generating EdDSA key pair..."
echo ""

# Export keys to files
PRIV_KEY_FILE="$REPO_ROOT/.sparkle_private_key.pem"
PUB_KEY_FILE="$REPO_ROOT/.sparkle_public_key.pem"

if [ -f "$PRIV_KEY_FILE" ]; then
    echo "⚠️  Private key already exists at $PRIV_KEY_FILE"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Generating new EdDSA key pair..."
"$GENERATE_KEYS" -f "$PRIV_KEY_FILE"

# Extract public key
PUB_KEY=$("$GENERATE_KEYS" -f "$PRIV_KEY_FILE" -p 2>/dev/null | grep -o '[^ ]*=$' | head -1)

echo ""
echo "=========================================="
echo "Keys Generated!"
echo "=========================================="
echo ""
echo "Private key file: $PRIV_KEY_FILE"
echo "⚠️  KEEP THIS FILE SECRET - Never commit it!"
echo ""
echo "Public key: $PUB_KEY"
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Add the private key to GitHub Secrets:"
echo "   - Name: SPARKLE_PRIVATE_KEY"
echo "   - Value: $(cat "$PRIV_KEY_FILE")"
echo ""
echo "2. Update Info.plist with the public key:"
echo "   Add to scripts/build/package-app.sh:"
echo "   SUPublicEDKey: $PUB_KEY"
echo ""
echo "3. Add .sparkle_private_key.pem to .gitignore"
echo ""

# Clean up temp dir if created
if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi
