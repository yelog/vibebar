#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/opencode-vibebar-plugin"
DIST_DIR="$ROOT_DIR/dist"

if [[ ! -f "$PLUGIN_DIR/package.json" ]]; then
  echo "package.json not found in $PLUGIN_DIR" >&2
  exit 1
fi

version="$(grep -E '"version"' "$PLUGIN_DIR/package.json" | head -n 1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
if [[ -z "$version" ]]; then
  echo "Unable to parse version from package.json" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
archive="$DIST_DIR/opencode-vibebar-plugin-$version.tgz"

echo "Packing OpenCode plugin $version -> $archive"
tar -czf "$archive" -C "$PLUGIN_DIR" .
shasum -a 256 "$archive"

cat <<EOF

Package complete.
Install locally with:
  cd "$PLUGIN_DIR" && npm install
Or use the tarball:
  npm install "$archive"
EOF
