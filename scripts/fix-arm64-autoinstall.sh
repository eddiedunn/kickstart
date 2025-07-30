#!/bin/bash
#
# Fix ARM64 Ubuntu autoinstall syntax issues
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INPUT_ISO="${1:-}"
WORK_DIR="${PROJECT_ROOT}/work-fix"
OUTPUT_DIR="${PROJECT_ROOT}/output"

if [ -z "$INPUT_ISO" ] || [ ! -f "$INPUT_ISO" ]; then
    echo "Usage: $0 <autoinstall-iso>"
    exit 1
fi

# Convert to absolute path
if [[ "$INPUT_ISO" != /* ]]; then
    INPUT_ISO="$(pwd)/$INPUT_ISO"
fi

echo "Fixing ARM64 autoinstall ISO: $(basename "$INPUT_ISO")"
echo "============================================"

# Cleanup and create work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Extract ISO
echo
echo "Extracting ISO contents..."
xorriso -osirrox on -indev "$INPUT_ISO" -extract / . 2>&1 | grep -v "Permission denied" || true
chmod -R u+w .

# Fix GRUB configurations
echo
echo "Fixing GRUB configurations for ARM64..."

# Fix boot/grub/grub.cfg - escape semicolon properly
if [ -f "boot/grub/grub.cfg" ]; then
    echo "Updating boot/grub/grub.cfg..."
    cp boot/grub/grub.cfg boot/grub/grub.cfg.bak
    
    # Method 1: Escape the semicolon
    perl -pi -e 's|ds=nocloud;s=/cdrom/nocloud/|ds=nocloud\\;s=/cdrom/nocloud/|g' boot/grub/grub.cfg
    
    # Increase timeout to give time to see menu
    perl -pi -e 's|timeout=1|timeout=3|g' boot/grub/grub.cfg
    
    echo "Changes made:"
    diff -u boot/grub/grub.cfg.bak boot/grub/grub.cfg || true
fi

# Check for EFI grub config (sometimes ARM64 uses this)
if [ -d "EFI/BOOT" ]; then
    echo
    echo "Checking for EFI boot configurations..."
    for cfg in EFI/BOOT/*.cfg EFI/BOOT/*.conf; do
        if [ -f "$cfg" ]; then
            echo "Found: $cfg"
            grep -H "linux\|autoinstall" "$cfg" || true
        fi
    done
fi

# Alternative method: Create a grub.cfg in EFI/BOOT if it doesn't exist
if [ ! -f "EFI/BOOT/grub.cfg" ] && [ -d "EFI/BOOT" ]; then
    echo
    echo "Creating EFI/BOOT/grub.cfg for ARM64..."
    cat > EFI/BOOT/grub.cfg << 'EOF'
set timeout=3
set default=0

menuentry "Ubuntu Server Autoinstall" {
    linux /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---
    initrd /casper/initrd
}
EOF
fi

# Double-check nocloud directory
echo
echo "Verifying nocloud directory..."
if [ -d "nocloud" ]; then
    echo "✓ nocloud directory exists"
    echo "  user-data: $(wc -l < nocloud/user-data) lines"
    echo "  meta-data: $(wc -l < nocloud/meta-data) lines"
else
    echo "✗ ERROR: nocloud directory missing!"
fi

# Build fixed ISO
echo
echo "Building fixed ISO..."
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_ISO="${OUTPUT_DIR}/ubuntu-22.04-arm64-autoinstall-fixed-${TIMESTAMP}.iso"

# Get original volume ID and truncate if needed
VOLUME_ID="Ubuntu-ARM64-Fixed"

# Build ISO with proper ARM64 support
# First try to extract mkisofs parameters from original ISO
if xorriso -indev "$INPUT_ISO" -report_el_torito as_mkisofs 2>/dev/null > mkisofs.opts; then
    echo "Using original ISO boot configuration..."
    eval xorriso -as mkisofs \
        -r \
        -V "'$VOLUME_ID'" \
        -o "'$OUTPUT_ISO'" \
        $(grep -v "^-V" mkisofs.opts | tr '\n' ' ') \
        . 2>&1
else
    # Fallback for ARM64
    echo "Using ARM64 fallback boot configuration..."
    xorriso -as mkisofs \
        -r \
        -V "$VOLUME_ID" \
        -o "$OUTPUT_ISO" \
        -J -joliet-long \
        -l \
        -e efi/boot/bootaa64.efi \
        -no-emul-boot \
        . 2>&1
fi

# Cleanup
cd "$PROJECT_ROOT"
rm -rf "$WORK_DIR"

# Report
if [ -f "$OUTPUT_ISO" ]; then
    echo
    echo "✓ Fixed ISO created successfully!"
    echo "  Output: $OUTPUT_ISO"
    echo "  Size: $(du -h "$OUTPUT_ISO" | cut -f1)"
    echo
    echo "To test:"
    echo "1. Update terraform.tfvars with new ISO path"
    echo "2. Run: tofu destroy && tofu apply"
    echo
    echo "The fixed ISO has:"
    echo "- Escaped semicolon in kernel parameters"
    echo "- Increased GRUB timeout to 3 seconds"
    echo "- Proper ARM64 EFI boot configuration"
else
    echo
    echo "✗ Failed to create fixed ISO"
    exit 1
fi