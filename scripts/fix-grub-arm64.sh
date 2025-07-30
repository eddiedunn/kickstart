#!/bin/bash
#
# Fix GRUB configuration for ARM64 autoinstall
#

set -euo pipefail

ISO_PATH="$1"
OUTPUT_ISO="$2"
WORK_DIR="/tmp/fix-grub-$$"

echo "Fixing GRUB for ARM64 autoinstall..."

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Extract ISO
xorriso -osirrox on -indev "$ISO_PATH" -extract / . 2>&1 | grep -v "Permission denied" || true
chmod -R u+w .

# Fix GRUB configuration - try different syntax variations
echo "Updating GRUB configurations..."

# Find all grub.cfg files
find . -name "grub.cfg" -type f | while read -r grub_file; do
    echo "Processing: $grub_file"
    
    # Create backup
    cp "$grub_file" "${grub_file}.bak"
    
    # Try URL encoding the semicolon
    perl -pi -e 's|autoinstall ds=nocloud;s=/cdrom/nocloud/|autoinstall ds=nocloud\\;s=/cdrom/nocloud/|g' "$grub_file"
    
    # Show the changes
    echo "Changes made:"
    diff -u "${grub_file}.bak" "$grub_file" || true
done

# Also check for boot.cfg (sometimes used on ARM64)
find . -name "boot.cfg" -type f | while read -r boot_file; do
    echo "Found boot.cfg: $boot_file"
    cat "$boot_file"
done

# Check EFI boot entries
if [ -d "EFI" ]; then
    echo
    echo "EFI directory structure:"
    find EFI -type f -name "*.cfg" -o -name "*.conf" | while read -r cfg; do
        echo "=== $cfg ==="
        head -20 "$cfg"
    done
fi

# Rebuild ISO
echo
echo "Rebuilding ISO..."
xorriso -as mkisofs \
    -r \
    -V "Ubuntu-ARM64-Autoinstall" \
    -o "$OUTPUT_ISO" \
    -J -joliet-long \
    -l \
    . 2>&1

# Cleanup
cd /
rm -rf "$WORK_DIR"

echo "Fixed ISO saved to: $OUTPUT_ISO"