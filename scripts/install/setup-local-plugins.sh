#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENCODE_PLUGIN_DIR="$ROOT_DIR/plugins/opencode-vibebar-plugin"
CLAUDE_PLUGIN_DIR="$ROOT_DIR/plugins/claude-vibebar-plugin"
DEFAULT_SOCKET_PATH="$HOME/Library/Application Support/VibeBar/runtime/agent.sock"

echo "== VibeBar local plugin setup =="
echo "repo: $ROOT_DIR"
echo

if [[ ! -d "$OPENCODE_PLUGIN_DIR" ]]; then
  echo "OpenCode plugin dir not found: $OPENCODE_PLUGIN_DIR" >&2
  exit 1
fi

if [[ ! -d "$CLAUDE_PLUGIN_DIR" ]]; then
  echo "Claude plugin dir not found: $CLAUDE_PLUGIN_DIR" >&2
  exit 1
fi

echo "[1/3] Configure OpenCode plugin"
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
mkdir -p "$OPENCODE_CONFIG_DIR"

if [[ -f "$OPENCODE_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
  tmp_file="$(mktemp)"
  jq --arg p "$OPENCODE_PLUGIN_DIR" '.plugin = (((.plugin // []) + [$p]) | unique)' "$OPENCODE_CONFIG_FILE" >"$tmp_file"
  mv "$tmp_file" "$OPENCODE_CONFIG_FILE"
  echo "Updated $OPENCODE_CONFIG_FILE"
else
  cat >"$OPENCODE_CONFIG_FILE" <<EOF
{
  "plugin": [
    "$OPENCODE_PLUGIN_DIR"
  ]
}
EOF
  echo "Wrote $OPENCODE_CONFIG_FILE"
  echo "Tip: install jq to merge with existing config automatically."
fi
echo

echo "[2/3] Install Claude plugin"
if command -v claude >/dev/null 2>&1; then
  if claude plugin install "$CLAUDE_PLUGIN_DIR"; then
    claude plugin enable vibebar-claude || true
    echo "Claude plugin install command executed."
  else
    echo "Claude plugin install failed. Please run manually:"
    echo "  claude plugin install \"$CLAUDE_PLUGIN_DIR\""
    echo "  claude plugin enable vibebar-claude"
  fi
else
  echo "claude command not found. Please install manually later:"
  echo "  claude plugin install \"$CLAUDE_PLUGIN_DIR\""
  echo "  claude plugin enable vibebar-claude"
fi
echo

echo "[3/3] Next steps"
echo "1. Start agent:"
echo "   swift run vibebar-agent --verbose"
echo "2. Ensure plugins can reach socket path:"
echo "   export VIBEBAR_AGENT_SOCKET=\"\${VIBEBAR_AGENT_SOCKET:-$DEFAULT_SOCKET_PATH}\""
echo "3. Start VibeBar menu app:"
echo "   swift run VibeBarApp"
