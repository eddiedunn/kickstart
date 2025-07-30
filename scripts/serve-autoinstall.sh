#!/bin/bash
#
# Serve autoinstall configuration via HTTP for ARM64 compatibility
#

set -euo pipefail

PORT="${1:-8080}"
CONFIG_DIR="${2:-./autoinstall}"

echo "Starting autoinstall HTTP server..."
echo "Configuration directory: $CONFIG_DIR"
echo "Port: $PORT"
echo
echo "To use this server, boot Ubuntu with:"
echo "  autoinstall ds=nocloud-net;s=http://$(hostname -I | awk '{print $1}'):$PORT/"
echo
echo "Press Ctrl+C to stop"
echo

cd "$CONFIG_DIR"
python3 -m http.server "$PORT"