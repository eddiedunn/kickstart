#!/bin/bash
#
# Minimal Ubuntu Autoinstall ISO Builder
# Simplified configuration that actually works
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${PROJECT_ROOT}/work"
OUTPUT_DIR="${PROJECT_ROOT}/output"

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
    
    # Get SSH keys
    SSH_KEYS=""
    for key in "$HOME"/.ssh/*.pub; do
        if [ -f "$key" ]; then
            KEY_CONTENT=$(cat "$key")
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
    
    # Update GRUB
    log_info "Updating GRUB configuration..."
    perl -pi -e 's|timeout=1|timeout=3|g' boot/grub/grub.cfg
    perl -pi -e 's|(linux\s+/casper/vmlinuz[^\s]*\s+)(.*?)(\s+---)|$1$2 autoinstall ds=nocloud\\;s=/cdrom/nocloud/$3|g' boot/grub/grub.cfg
    
    # Build ISO
    local iso_name="ubuntu-minimal-autoinstall-$(date +%Y%m%d-%H%M%S).iso"
    local output_iso="${OUTPUT_DIR}/${iso_name}"
    
    log_info "Building ISO..."
    if xorriso -indev "$input_iso" -report_el_torito as_mkisofs 2>/dev/null > mkisofs.opts; then
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