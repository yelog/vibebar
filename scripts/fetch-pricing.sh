#!/bin/bash
set -e

PRICING_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="$PROJECT_ROOT/Sources/VibeBarApp/Resources/pricing.json"

echo "Fetching LiteLLM pricing data..."
echo "  URL: $PRICING_URL"
echo "  Output: $OUTPUT_FILE"

curl -sL "$PRICING_URL" -o "$OUTPUT_FILE"

# Verify JSON validity
python3 -c "import json; json.load(open('$OUTPUT_FILE'))"

echo "✓ Pricing data saved to $OUTPUT_FILE"
echo "  File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "  Model count: $(python3 -c "import json; print(len(json.load(open('$OUTPUT_FILE'))))" "$OUTPUT_FILE")"