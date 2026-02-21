#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/opencode-vibebar-plugin"

if [[ ! -f "$PLUGIN_DIR/package.json" ]]; then
  echo "package.json not found in $PLUGIN_DIR" >&2
  exit 1
fi

if [[ -n "${NPM_TOKEN:-}" ]]; then
  npm config set //registry.npmjs.org/:_authToken "$NPM_TOKEN"
fi

echo "Publishing OpenCode plugin from: $PLUGIN_DIR"
cd "$PLUGIN_DIR"
npm publish --access public "$@"
