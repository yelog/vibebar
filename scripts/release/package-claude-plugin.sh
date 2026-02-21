#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/claude-vibebar-plugin"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
DIST_DIR="$ROOT_DIR/dist"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Claude plugin manifest not found: $MANIFEST" >&2
  exit 1
fi

version="$(grep -E '"version"' "$MANIFEST" | head -n 1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
if [[ -z "$version" ]]; then
  echo "Unable to parse version from $MANIFEST" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
archive="$DIST_DIR/claude-vibebar-plugin-$version.tgz"

echo "Packing Claude plugin $version -> $archive"
tar -czf "$archive" -C "$PLUGIN_DIR" .
shasum -a 256 "$archive"

cat <<EOF

Package complete.
Suggested release flow:
1) Create git tag for this version.
2) Publish/update your Claude marketplace source repository.
3) Announce install source:
   claude plugin install <source>
EOF
