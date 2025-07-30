#!/bin/bash
#
# Diagnose ARM64 Ubuntu boot issues
#

set -euo pipefail

ISO_PATH="${1:-}"
TEMP_DIR="/tmp/arm64-diagnose-$$"

if [ -z "$ISO_PATH" ]; then
    echo "Usage: $0 <iso-path>"
    exit 1
fi

# Convert to absolute path
if [[ "$ISO_PATH" != /* ]]; then
    ISO_PATH="$(pwd)/$ISO_PATH"
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "Error: ISO file not found: $ISO_PATH"
    exit 1
fi

echo "Diagnosing ARM64 Ubuntu ISO: $ISO_PATH"
echo "=================================="

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Extract ISO
echo
echo "Extracting ISO contents..."
xorriso -osirrox on -indev "$ISO_PATH" -extract / . 2>&1 >/dev/null || true

# Check boot structure
echo
echo "Boot structure:"
find . -type d -name "*boot*" -o -name "*EFI*" -o -name "*efi*" | sort

# Check for GRUB configurations
echo
echo "GRUB configurations found:"
find . -name "grub.cfg" -o -name "*.conf" -o -name "*.cfg" | grep -E "(grub|boot|efi)" | while read -r cfg; do
    echo
    echo "=== $cfg ==="
    if grep -q "menuentry\|linux\|autoinstall" "$cfg" 2>/dev/null; then
        grep -A 3 -B 1 "menuentry\|linux\|autoinstall" "$cfg" | head -20
    else
        head -10 "$cfg"
    fi
done

# Check cloud-init data
echo
echo "Cloud-init/Autoinstall data:"
if [ -d "nocloud" ]; then
    echo "✓ Found nocloud directory"
    ls -la nocloud/
    echo
    echo "user-data header:"
    head -5 nocloud/user-data 2>/dev/null || echo "  ERROR: Cannot read user-data"
else
    echo "✗ No nocloud directory found!"
fi

# Check kernel command line in various locations
echo
echo "Checking kernel command line parameters:"
for file in boot/grub/grub.cfg boot/grub/efi.cfg EFI/BOOT/grub.cfg; do
    if [ -f "$file" ]; then
        echo
        echo "In $file:"
        grep -o "linux.*autoinstall[^\"]*" "$file" 2>/dev/null | head -5 || echo "  No autoinstall parameters found"
    fi
done

# Check for ARM64-specific files
echo
echo "ARM64-specific boot files:"
find . -name "*aa64*" -o -name "*arm64*" | grep -E "\.(efi|EFI)$"

# Check ISO boot catalog
echo
echo "ISO boot information:"
xorriso -indev "$ISO_PATH" -report_el_torito plain 2>&1 | grep -E "(Platform|Boot|Load)" || echo "  No El Torito boot info"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo
echo "Diagnosis complete!"
echo
echo "Common ARM64 issues:"
echo "1. Semicolon in ds=nocloud;s= needs escaping: ds=nocloud\\;s="
echo "2. Some ARM64 systems need ds=nocloud-net instead of ds=nocloud"
echo "3. EFI boot may use different config file than boot/grub/grub.cfg"
echo "4. Timeout might be too short - press ESC quickly at boot"