#!/bin/bash
# VibeBar hook script for GitHub Copilot CLI
# Writes session state to ~/.copilot/vibebar/{pid}.json so VibeBar can track activity.
#
# Install: add this script path to your .github/hooks/hooks.json
# See: https://docs.github.com/en/copilot/how-tos/copilot-cli/use-hooks

HOOK_TYPE="${1:-unknown}"
INPUT="$(cat)"

# Resolve copilot process PID via parent process
COPILOT_PID=$PPID

# Extract cwd from hook JSON input
CWD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null)

if [ -z "$CWD" ]; then
    CWD="$(pwd)"
fi

STATE_DIR="$HOME/.copilot/vibebar"
mkdir -p "$STATE_DIR"

TIMESTAMP=$(python3 -c "import time; print(time.time())" 2>/dev/null || date +%s)
STATE_FILE="$STATE_DIR/$COPILOT_PID.json"

case "$HOOK_TYPE" in
    session_end)
        rm -f "$STATE_FILE" 2>/dev/null
        exit 0
        ;;
    *)
        printf '{"pid":%d,"last_event":"%s","cwd":"%s","timestamp":%s}\n' \
            "$COPILOT_PID" "$HOOK_TYPE" "$CWD" "$TIMESTAMP" > "$STATE_FILE"
        ;;
esac

exit 0
