#!/bin/bash
#
# build-autoinstall-iso.sh - Create Custom Ubuntu Autoinstall ISO
#
# PURPOSE:
#   Creates a custom Ubuntu Server ISO with embedded autoinstall configuration.
#   The resulting ISO performs unattended installation with predefined settings.
#   This script is the foundation for automated VM deployments in Parallels Desktop.
#
# USAGE:
#   ./build-autoinstall-iso.sh <ubuntu-server-arm64.iso>
#
# PARAMETERS:
#   $1 - Path to original Ubuntu Server ISO (required)
#        Download from: https://ubuntu.com/download/server/arm
#        Supports both ARM64 (Apple Silicon) and AMD64 (Intel) ISOs
#
# OUTPUT:
#   Creates ISO in output/ directory with timestamp:
#   ubuntu-minimal-autoinstall-YYYYMMDD-HHMMSS.iso
#
# EXAMPLE:
#   # Basic usage
#   ./build-autoinstall-iso.sh ~/Downloads/ubuntu-22.04.5-live-server-arm64.iso
#   
#   # Using relative path
#   ./build-autoinstall-iso.sh ../isos/ubuntu-22.04.5-live-server-arm64.iso
#
# AUTOINSTALL FEATURES:
#   - Unattended installation (no user prompts)
#   - DHCP network configuration (works with Parallels NAT)
#   - Direct storage layout (uses entire disk)
#   - Default user: ubuntu (password: ubuntu)
#   - SSH server with key-based authentication
#   - Essential packages: qemu-guest-agent, cloud-init, curl, vim
#   - Cloud-init enabled for post-boot configuration
#
# PREREQUISITES:
#   - xorriso: For ISO manipulation
#     macOS: brew install xorriso
#     Ubuntu: apt-get install xorriso
#   - SSH keys: Automatically includes all public keys from ~/.ssh/*.pub
#   - Disk space: ~5GB free for ISO creation workspace
#
# SECURITY NOTES:
#   - Default password is SHA-512 hashed ('ubuntu')
#   - SSH password authentication disabled when keys are present
#   - All discovered SSH public keys are automatically added
#   - Customize autoinstall/user-data for production deployments
#   - Consider using different passwords for different environments
#
# HOW IT WORKS:
#   1. Extracts contents of original Ubuntu ISO
#   2. Injects custom autoinstall configuration (user-data)
#   3. Modifies GRUB bootloader to add autoinstall parameters
#   4. Rebuilds ISO with same boot configuration as original
#   5. Cleans up temporary workspace
#
# TROUBLESHOOTING:
#   - "Permission denied" errors: Check file permissions on ISO
#   - "xorriso not found": Install xorriso package
#   - "No SSH keys found": Generate with: ssh-keygen -t ed25519
#   - Boot failures: Verify ISO architecture matches your Mac
#
# RELATED FILES:
#   - autoinstall/user-data: Autoinstall configuration template
#   - scripts/deploy-vm.sh: Deploy VMs using created ISO
#   - scripts/validate-config.sh: Validate autoinstall syntax
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Script location
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"                       # Project root
WORK_DIR="${PROJECT_ROOT}/work"                               # Temporary workspace
OUTPUT_DIR="${PROJECT_ROOT}/output"                           # ISO output directory

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

cleanup_workspace() {
    if [ -d "$WORK_DIR" ]; then
        chmod -R u+w "$WORK_DIR" 2>/dev/null || true
        rm -rf "$WORK_DIR"
    fi
}

# Main function
main() {
    local input_iso="${1:-}"
    
    if [ -z "$input_iso" ] || [ ! -f "$input_iso" ]; then
        echo "Usage: $0 <ubuntu-server-arm64.iso>"
        exit 1
    fi
    
    # Convert to absolute path
    input_iso=$(cd "$(dirname "$input_iso")" && pwd)/$(basename "$input_iso")
    
    # Prepare workspace
    cleanup_workspace
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
    
    # Extract ISO
    log_info "Extracting ISO contents..."
    cd "$WORK_DIR"
    xorriso -osirrox on -indev "$input_iso" -extract / . 2>&1 | grep -v "Permission denied" || true
    chmod -R u+w .
    
    # Create minimal autoinstall configuration
    log_info "Creating minimal autoinstall configuration..."
    mkdir -p nocloud
    
    # Collect SSH public keys for passwordless access
    # Searches for all .pub files in user's .ssh directory
    # These keys will be added to the ubuntu user's authorized_keys
    SSH_KEYS=""
    for key in "$HOME"/.ssh/*.pub; do
        if [ -f "$key" ]; then
            KEY_CONTENT=$(cat "$key")
            # Format for YAML list with proper indentation
            SSH_KEYS="${SSH_KEYS}      - \"$KEY_CONTENT\"\n"
        fi
    done
    
    cat > nocloud/user-data << EOF
#cloud-config
autoinstall:
  version: 1
  
  locale: en_US.UTF-8
  keyboard:
    layout: us
  
  network:
    version: 2
    ethernets:
      enp0s5:
        dhcp4: true
  
  storage:
    layout:
      name: lvm
  
  identity:
    hostname: ubuntu-server
    username: ubuntu
    password: "\$6\$rounds=4096\$8dkK1P/oE\$2DGKKt0wLlTVJ7USY.0jN9du8FetmEr51yjPyeiR.zKE3DGFcitNL/nF1l62BLJNR87lQZixObuXYny.Mf17K1"
  
  ssh:
    install-server: true
    authorized-keys:
$(echo -e "$SSH_KEYS")
  
  packages:
    - qemu-guest-agent
    - openssh-server
    - curl
    - vim
  
  shutdown: reboot
EOF
    
    # Create meta-data
    cat > nocloud/meta-data << EOF
instance-id: iid-local01
local-hostname: ubuntu-server
EOF
    
    # Update GRUB bootloader configuration for autoinstall
    log_info "Updating GRUB configuration..."
    
    # Increase boot timeout from 1 to 3 seconds
    # This gives users a chance to interrupt boot if needed
    perl -pi -e 's|timeout=1|timeout=3|g' boot/grub/grub.cfg
    
    # Add autoinstall kernel parameters to enable unattended installation
    # - autoinstall: Enables the autoinstall mode in subiquity
    # - ds=nocloud;s=/cdrom/nocloud/: Points to our cloud-init datasource
    #   The semicolon must be escaped (\;) in GRUB
    perl -pi -e 's|(linux\s+/casper/vmlinuz[^\s]*\s+)(.*?)(\s+---)|$1$2 autoinstall ds=nocloud\\;s=/cdrom/nocloud/$3|g' boot/grub/grub.cfg
    
    # Build the custom ISO with autoinstall configuration
    local iso_name="ubuntu-minimal-autoinstall-$(date +%Y%m%d-%H%M%S).iso"
    local output_iso="${OUTPUT_DIR}/${iso_name}"
    
    log_info "Building ISO..."
    
    # Extract El Torito boot configuration from original ISO
    # This ensures our custom ISO boots the same way as the original
    if xorriso -indev "$input_iso" -report_el_torito as_mkisofs 2>/dev/null > mkisofs.opts; then
        # Build new ISO using extracted boot parameters
        # -r: Rock Ridge extensions for proper file permissions
        # -V: Volume label visible when ISO is mounted
        # -o: Output file path
        eval xorriso -as mkisofs \
            -r \
            -V "'Ubuntu-Minimal-Autoinstall'" \
            -o "'$output_iso'" \
            $(grep -v "^-V" mkisofs.opts | tr '\n' ' ') \
            . 2>&1
    fi
    
    # Cleanup
    cd "$PROJECT_ROOT"
    cleanup_workspace
    
    # Report
    if [ -f "$output_iso" ]; then
        echo
        log_info "✓ ISO created successfully!"
        echo "Output: $output_iso"
        echo "Size: $(du -h "$output_iso" | cut -f1)"
    else
        log_error "Failed to create ISO"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_workspace EXIT

# Run main
main "$@"