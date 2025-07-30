#!/bin/bash
#
# Diagnose autoinstall issues
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ISO_PATH="$1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ -z "${ISO_PATH:-}" ] || [ ! -f "$ISO_PATH" ]; then
    echo "Usage: $0 <iso-path>"
    exit 1
fi

echo
echo -e "${GREEN}Autoinstall ISO Diagnostics${NC}"
echo -e "${GREEN}==========================${NC}"
echo

# Create temp directory
TEMP_DIR="${PROJECT_ROOT}/iso_diagnose"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Extract ISO
log_info "Extracting ISO contents..."
cd "$TEMP_DIR"
xorriso -osirrox on -indev "$ISO_PATH" -extract / . 2>&1 >/dev/null || true

# Check for nocloud directory
log_info "Checking for nocloud directory..."
if [ -d "nocloud" ]; then
    log_info "✓ Found nocloud directory"
    ls -la nocloud/
else
    log_error "✗ nocloud directory not found!"
fi

# Check grub configuration
log_info "Checking GRUB configuration..."
if [ -f "boot/grub/grub.cfg" ]; then
    log_info "✓ Found grub.cfg"
    echo
    echo "Autoinstall entries in grub.cfg:"
    grep -n "autoinstall" boot/grub/grub.cfg || log_warn "No autoinstall entries found!"
    echo
    echo "First menuentry:"
    grep -A 5 "menuentry" boot/grub/grub.cfg | head -10
else
    log_error "✗ grub.cfg not found!"
fi

# Check user-data
if [ -f "nocloud/user-data" ]; then
    echo
    log_info "Checking user-data format..."
    head -5 nocloud/user-data
    echo
    
    # Validate YAML
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('nocloud/user-data'))" 2>&1 && \
            log_info "✓ user-data is valid YAML" || \
            log_error "✗ user-data has YAML syntax errors!"
    fi
fi

# Check meta-data
if [ -f "nocloud/meta-data" ]; then
    echo
    log_info "meta-data contents:"
    cat nocloud/meta-data
fi

# Check for ARM64-specific boot files
echo
log_info "Checking for ARM64 boot files..."
find . -name "grub*.efi" -o -name "shimaa64.efi" -o -name "mmaa64.efi" | while read -r file; do
    echo "  Found: $file"
done

# Check ISO boot info
echo
log_info "ISO boot information:"
xorriso -indev "$ISO_PATH" -report_el_torito plain 2>&1 | grep -E "(Boot|Platform)" || true

# Cleanup
cd "$PROJECT_ROOT"
rm -rf "$TEMP_DIR"

echo
log_info "Diagnosis complete!"
echo
echo "Common issues:"
echo "1. ARM64 uses different boot mechanism than x86"
echo "2. Autoinstall parameters must be in kernel command line"
echo "3. The 'ds=nocloud;s=/cdrom/nocloud/' syntax is critical"
echo "4. GRUB timeout might be too short"
echo
echo "To test manually:"
echo "1. Boot the VM and press 'e' at GRUB menu"
echo "2. Check if 'autoinstall ds=nocloud;s=/cdrom/nocloud/' is present"
echo "3. If not, add it manually and press Ctrl+X to boot"