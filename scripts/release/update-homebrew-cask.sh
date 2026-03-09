#!/bin/bash
set -euo pipefail

# Update Homebrew cask with new version and SHA256
# Usage: bash scripts/release/update-homebrew-cask.sh <version> <sha256>

VERSION="${1:?Usage: $0 <version> <sha256>}"
SHA256="${2:?Usage: $0 <version> <sha256>}"

TAP_REPO="yelog/homebrew-vibebar"
CASK_FILE="Casks/vibebar.rb"

# Skip pre-release versions
if [[ "$VERSION" =~ -(beta|alpha|rc)\.[0-9]+$ ]]; then
  echo "Skipping pre-release version: $VERSION"
  exit 0
fi

if [ -z "${HOMEBREW_TAP_TOKEN:-}" ]; then
  echo "Error: HOMEBREW_TAP_TOKEN is not set"
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning tap repository..."
git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" "$WORK_DIR/tap"
cd "$WORK_DIR/tap"

echo "Updating cask to version $VERSION..."
sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" "$CASK_FILE"

git add "$CASK_FILE"
git commit -m "Update VibeBar to $VERSION"
git push origin main

echo "Homebrew cask updated to $VERSION"
