#!/bin/bash
#
# Capture VM screen to diagnose boot issues
#

VM_NAME="${1:-ubuntu-server}"
OUTPUT_DIR="$(dirname "$0")/../output"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCREENSHOT_PATH="$OUTPUT_DIR/vm-screenshot-${TIMESTAMP}.png"

# Create output directory if needed
mkdir -p "$OUTPUT_DIR"

# Capture screenshot
prlctl capture "$VM_NAME" --file "$SCREENSHOT_PATH"

echo "Screenshot saved to: $SCREENSHOT_PATH"

# Try to use OCR to read the screen content if available
if command -v tesseract &> /dev/null; then
    echo
    echo "Attempting OCR on screenshot..."
    tesseract "$SCREENSHOT_PATH" "$OUTPUT_DIR/vm-screenshot-${TIMESTAMP}" 2>/dev/null
    if [ -f "$OUTPUT_DIR/vm-screenshot-${TIMESTAMP}.txt" ]; then
        echo "OCR text:"
        cat "$OUTPUT_DIR/vm-screenshot-${TIMESTAMP}.txt"
    fi
fi