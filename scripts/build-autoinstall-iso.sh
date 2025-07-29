#!/bin/bash
#
# Build Ubuntu 22.04 ARM64 autoinstall ISO for Parallels
# This script creates a custom ISO with embedded autoinstall configuration
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${PROJECT_ROOT}/work"
OUTPUT_DIR="${PROJECT_ROOT}/output"
AUTOINSTALL_DIR="${PROJECT_ROOT}/autoinstall"

# Input ISO path
INPUT_ISO="${1:-/Volumes/SAMSUNG/isos/ubuntu-22.04.5-live-server-arm64.iso}"
OUTPUT_ISO="${OUTPUT_DIR}/ubuntu-22.04.5-autoinstall-arm64.iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    for tool in xorriso 7z mkisofs; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: brew install p7zip xorriso cdrtools"
        exit 1
    fi
    
    # Check if input ISO exists
    if [ ! -f "$INPUT_ISO" ]; then
        log_error "Input ISO not found: $INPUT_ISO"
        exit 1
    fi
    
    # Check if autoinstall files exist
    if [ ! -f "${AUTOINSTALL_DIR}/user-data" ]; then
        log_error "user-data file not found in ${AUTOINSTALL_DIR}"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

prepare_workspace() {
    log_info "Preparing workspace..."
    
    # Clean up previous work
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    log_info "Workspace prepared at $WORK_DIR"
}

extract_iso() {
    log_info "Extracting ISO contents..."
    
    cd "$WORK_DIR"
    
    # Extract ISO using 7z (more reliable on macOS)
    7z x -y "$INPUT_ISO" > /dev/null 2>&1
    
    # Make the extracted contents writable
    chmod -R u+w .
    
    log_info "ISO extracted successfully"
}

inject_autoinstall() {
    log_info "Injecting autoinstall configuration..."
    
    cd "$WORK_DIR"
    
    # Create nocloud directory for autoinstall
    mkdir -p nocloud
    
    # Copy autoinstall files
    cp "${AUTOINSTALL_DIR}/user-data" nocloud/
    cp "${AUTOINSTALL_DIR}/meta-data" nocloud/
    
    # Modify boot configuration for autoinstall
    # For ARM64, we need to modify grub.cfg
    if [ -f "boot/grub/grub.cfg" ]; then
        log_info "Modifying GRUB configuration for autoinstall..."
        
        # Backup original
        cp boot/grub/grub.cfg boot/grub/grub.cfg.orig
        
        # Add autoinstall parameters to the default menuentry
        # Using sed to add autoinstall parameters
        sed -i.bak 's|linux[[:space:]]\+/casper/vmlinuz|& autoinstall ds=nocloud;s=/cdrom/nocloud/ cloud-config-url=/cdrom/nocloud/|g' boot/grub/grub.cfg
        
        # Set timeout to 1 second for faster boot
        sed -i.bak 's/timeout=30/timeout=1/g' boot/grub/grub.cfg
    fi
    
    # For UEFI boot (which Parallels uses on ARM64)
    if [ -f "EFI/boot/grub.cfg" ]; then
        log_info "Modifying EFI GRUB configuration..."
        
        cp EFI/boot/grub.cfg EFI/boot/grub.cfg.orig
        
        # Add autoinstall parameters
        sed -i.bak 's|linux[[:space:]]\+/casper/vmlinuz|& autoinstall ds=nocloud;s=/cdrom/nocloud/ cloud-config-url=/cdrom/nocloud/|g' EFI/boot/grub.cfg
        
        # Set timeout
        sed -i.bak 's/timeout=30/timeout=1/g' EFI/boot/grub.cfg
    fi
    
    # Skip cloud-init validation on macOS (not available)
    log_info "Skipping cloud-init validation (not available on macOS)"
    
    log_info "Autoinstall configuration injected"
}

create_iso() {
    log_info "Creating new ISO..."
    
    cd "$WORK_DIR"
    
    # Extract boot configuration from original ISO
    log_info "Extracting boot configuration from original ISO..."
    xorriso -indev "$INPUT_ISO" \
        -report_el_torito as_mkisofs \
        > boot_config.txt 2>/dev/null || true
    
    # Get volume ID from original ISO
    VOLUME_ID=$(xorriso -indev "$INPUT_ISO" -pvd_info 2>&1 | grep "Volume Id" | cut -d: -f2 | xargs || echo "Ubuntu-Autoinstall")
    
    log_info "Using volume ID: $VOLUME_ID"
    
    # For ARM64, we need to handle this differently
    # Check if we have EFI boot files
    if [ -f "efi/boot/bootaa64.efi" ]; then
        log_info "Creating ARM64 EFI bootable ISO..."
        
        # Create ISO with proper EFI boot for ARM64
        xorriso -as mkisofs \
            -r \
            -V "$VOLUME_ID" \
            -J -joliet-long \
            -l \
            -iso-level 3 \
            -no-pad \
            -o "$OUTPUT_ISO" \
            .
    else
        log_error "EFI boot files not found. Cannot create bootable ISO."
        exit 1
    fi
    
    log_info "ISO created at $OUTPUT_ISO"
}

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$WORK_DIR"
    log_info "Cleanup complete"
}

print_summary() {
    echo
    log_info "Build complete!"
    echo
    echo "Output ISO: $OUTPUT_ISO"
    echo "ISO size: $(du -h "$OUTPUT_ISO" | cut -f1)"
    echo
    echo "This ISO will:"
    echo "  - Boot automatically with 1-second timeout"
    echo "  - Install Ubuntu 22.04 without any prompts"
    echo "  - Configure networking via DHCP"
    echo "  - Create a temporary 'ubuntu' user"
    echo "  - Enable cloud-init for OpenTofu configuration"
    echo
    echo "To use with Parallels and OpenTofu:"
    echo "  1. Create VM with this ISO"
    echo "  2. Pass cloud-init data via Parallels for:"
    echo "     - Hostname"
    echo "     - SSH public keys"
    echo "     - Additional configuration"
}

# Main execution
main() {
    log_info "Ubuntu 22.04 ARM64 Autoinstall ISO Builder"
    log_info "=========================================="
    
    check_prerequisites
    prepare_workspace
    extract_iso
    inject_autoinstall
    create_iso
    cleanup
    print_summary
}

# Run main function
main "$@"