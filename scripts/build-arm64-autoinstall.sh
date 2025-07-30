#!/bin/bash
#
# Ubuntu 22.04 ARM64 Autoinstall ISO Builder for Parallels
# Uses alternative approaches for ARM64 compatibility
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${PROJECT_ROOT}/work-arm64"
OUTPUT_DIR="${PROJECT_ROOT}/output"

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

cleanup_workspace() {
    if [ -d "$WORK_DIR" ]; then
        chmod -R u+w "$WORK_DIR" 2>/dev/null || true
        rm -rf "$WORK_DIR"
    fi
}

update_grub_arm64() {
    local work_dir="$1"
    
    log_info "Applying ARM64-specific GRUB configuration..."
    
    # Find all grub.cfg files
    find "$work_dir" -name "grub.cfg" -type f | while read -r grub_file; do
        log_info "Updating: $grub_file"
        
        # Backup original
        cp "$grub_file" "${grub_file}.orig"
        
        # Create new grub.cfg with ARM64-compatible syntax
        cat > "$grub_file" << 'EOF'
set timeout=1
set default="0"

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

# Main autoinstall entry
menuentry "Ubuntu Server Autoinstall" {
    set gfxpayload=keep
    # Method 1: URL-encoded semicolon
    linux /casper/vmlinuz autoinstall ds=nocloud%3Bs=/cdrom/nocloud/ quiet ---
    initrd /casper/initrd
}

# Alternative method 1: Using cloud-config-url
menuentry "Ubuntu Server Autoinstall (Alt 1)" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall cloud-config-url=/cdrom/nocloud/user-data quiet ---
    initrd /casper/initrd
}

# Alternative method 2: Space-separated
menuentry "Ubuntu Server Autoinstall (Alt 2)" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall ds=nocloud s=/cdrom/nocloud/ quiet ---
    initrd /casper/initrd
}

# Manual install fallback
menuentry "Ubuntu Server Manual Install" {
    set gfxpayload=keep
    linux /casper/vmlinuz quiet ---
    initrd /casper/initrd
}

# HWE kernel options
menuentry "Ubuntu Server with HWE kernel (Autoinstall)" {
    set gfxpayload=keep
    linux /casper/hwe-vmlinuz autoinstall ds=nocloud%3Bs=/cdrom/nocloud/ quiet ---
    initrd /casper/hwe-initrd
}

menuentry 'Boot from next volume' {
    exit 1
}

menuentry 'UEFI Firmware Settings' {
    fwsetup
}
EOF
    done
}

create_cloud_init_network_fix() {
    local work_dir="$1"
    
    # Create an additional network configuration that's more ARM64-friendly
    cat > "$work_dir/nocloud/network-config" << 'EOF'
version: 2
ethernets:
  any:
    match:
      name: "en*"
    dhcp4: true
    optional: true
  any-eth:
    match:
      name: "eth*"
    dhcp4: true
    optional: true
EOF
}

create_efi_startup_script() {
    local work_dir="$1"
    
    # Create EFI startup script for better ARM64 compatibility
    if [ -d "$work_dir/EFI/BOOT" ]; then
        cat > "$work_dir/EFI/BOOT/startup.nsh" << 'EOF'
@echo -off
echo "Ubuntu 22.04 ARM64 Autoinstall"
echo "Starting in 3 seconds..."
stall 3000000
\EFI\ubuntu\grubaa64.efi
EOF
        
        # Also create in root
        cp "$work_dir/EFI/BOOT/startup.nsh" "$work_dir/startup.nsh" 2>/dev/null || true
    fi
}

main() {
    local input_iso="${1:-}"
    
    echo
    echo -e "${GREEN}Ubuntu 22.04 ARM64 Autoinstall Builder (Parallels)${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo
    
    if [ -z "$input_iso" ] || [ ! -f "$input_iso" ]; then
        echo "Usage: $0 <ubuntu-22.04-arm64.iso>"
        echo
        echo "This script creates an ARM64-compatible autoinstall ISO"
        echo "with multiple boot methods for better compatibility"
        exit 1
    fi
    
    # Verify ARM64 ISO
    if ! [[ "$input_iso" =~ arm64|aarch64 ]]; then
        log_error "This script is for ARM64 ISOs only!"
        log_info "Detected: $input_iso"
        exit 1
    fi
    
    # Convert to absolute path
    input_iso=$(cd "$(dirname "$input_iso")" && pwd)/$(basename "$input_iso")
    
    # Select SSH keys (reuse logic from original script)
    log_info "Select SSH keys to embed..."
    local ssh_keys=()
    for key in "$HOME"/.ssh/*.pub; do
        if [ -f "$key" ]; then
            ssh_keys+=("$key")
            log_info "Adding SSH key: $(basename "$key")"
        fi
    done
    
    if [ ${#ssh_keys[@]} -eq 0 ]; then
        log_error "No SSH keys found in ~/.ssh/"
        exit 1
    fi
    
    # Prepare workspace
    cleanup_workspace
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
    
    # Extract ISO
    log_info "Extracting ISO contents..."
    cd "$WORK_DIR"
    xorriso -osirrox on -indev "$input_iso" -extract / . 2>&1 | grep -v "Permission denied" || true
    chmod -R u+w .
    
    # Create autoinstall configuration
    log_info "Creating ARM64-optimized autoinstall configuration..."
    mkdir -p nocloud
    
    cat > nocloud/user-data << 'EOF'
#cloud-config
autoinstall:
  version: 1
  
  # Explicitly set to non-interactive
  interactive-sections: []
  
  # Refresh installer to ensure we have the latest
  refresh-installer:
    update: no
  
  locale: en_US.UTF-8
  keyboard:
    layout: us
    variant: ""
  
  # ARM64-friendly network configuration
  network:
    version: 2
    renderer: networkd
    ethernets:
      id0:
        match:
          name: en*
        dhcp4: true
        optional: true
      id1:
        match:
          name: eth*
        dhcp4: true
        optional: true
  
  # Simple storage layout for ARM64
  storage:
    layout:
      name: lvm
      sizing-policy: all
  
  identity:
    hostname: ubuntu-arm64
    username: ubuntu
    # Password: ubuntu (will be locked)
    password: "$6$rounds=4096$8dkK1P/oE$2DGKKt0wLlTVJ7USY.0jN9du8FetmEr51yjPyeiR.zKE3DGFcitNL/nF1l62BLJNR87lQZixObuXYny.Mf17K1"
  
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
EOF
    
    # Add SSH keys
    for key_file in "${ssh_keys[@]}"; do
        echo "      - $(cat "$key_file")" >> nocloud/user-data
    done
    
    cat >> nocloud/user-data << 'EOF'
  
  # Essential packages for ARM64 VMs
  packages:
    - qemu-guest-agent
    - cloud-init
    - openssh-server
    - curl
    - wget
    - vim
    - net-tools
    - linux-tools-virtual
    - linux-cloud-tools-virtual
  
  late-commands:
    # Lock the password
    - curtin in-target --target=/target -- passwd -l ubuntu
    # Fix permissions
    - curtin in-target --target=/target -- chmod 700 /home/ubuntu/.ssh
    - curtin in-target --target=/target -- chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    # Enable essential services
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
    # ARM64 performance modules
    - |
      cat <<MODULES >> /target/etc/modules
      virtio_net
      virtio_blk
      virtio_scsi
      virtio_balloon
      virtio_console
      MODULES
    # Remove cloud-init network artifacts
    - rm -f /target/etc/cloud/cloud.cfg.d/50-curtin-networking.cfg
    - rm -f /target/etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
    # Set a custom MOTD
    - echo "Ubuntu 22.04 ARM64 - Autoinstalled for Parallels" > /target/etc/motd
  
  # Ensure proper shutdown
  shutdown: reboot
  
  # Error handling
  error-commands:
    - echo "Autoinstall failed! Check /var/log/installer/autoinstall-user-data" > /dev/console
EOF
    
    # Create meta-data
    cat > nocloud/meta-data << EOF
instance-id: ubuntu-arm64-$(date +%s)
local-hostname: ubuntu-arm64
EOF
    
    # Create network-config for cloud-init
    create_cloud_init_network_fix "$WORK_DIR"
    
    # Update GRUB with ARM64-specific configuration
    update_grub_arm64 "$WORK_DIR"
    
    # Create EFI startup script
    create_efi_startup_script "$WORK_DIR"
    
    # Build the ISO
    local output_name="ubuntu-22.04-arm64-autoinstall-parallels-$(date +%Y%m%d-%H%M%S).iso"
    local output_iso="${OUTPUT_DIR}/${output_name}"
    
    log_info "Building ARM64 autoinstall ISO..."
    
    # Use xorriso with ARM64-compatible options
    xorriso -as mkisofs \
        -r \
        -V "Ubuntu-22.04-ARM64-Auto" \
        -o "$output_iso" \
        -J -joliet-long \
        -l \
        -no-pad \
        -iso-level 3 \
        . 2>&1 || {
        log_error "Failed to create ISO"
        exit 1
    }
    
    # Cleanup
    cd "$PROJECT_ROOT"
    cleanup_workspace
    
    # Report success
    if [ -f "$output_iso" ]; then
        local iso_size=$(du -h "$output_iso" | cut -f1)
        
        echo
        log_info "✓ ARM64 autoinstall ISO created successfully!"
        echo
        echo -e "${GREEN}Output:${NC} $output_iso"
        echo -e "${GREEN}Size:${NC} $iso_size"
        echo
        echo "This ISO includes:"
        echo "  • Multiple autoinstall boot methods"
        echo "  • URL-encoded semicolon for ARM64 compatibility"
        echo "  • Alternative cloud-config-url method"
        echo "  • EFI startup script"
        echo "  • Network configuration for various interfaces"
        echo
        echo "Boot options:"
        echo "  1. Default: Uses URL-encoded ds=nocloud"
        echo "  2. Alt 1: Uses cloud-config-url parameter"
        echo "  3. Alt 2: Uses space-separated parameters"
        echo "  4. Manual: Falls back to interactive install"
        echo
        echo "To test:"
        echo "  1. Create Parallels VM with EFI firmware"
        echo "  2. Attach this ISO"
        echo "  3. Boot and observe which method works"
        echo
        echo "If autoinstall still doesn't trigger:"
        echo "  - Check VM console with Alt+F2 during boot"
        echo "  - Look at /var/log/cloud-init.log"
        echo "  - Try the HTTP server method instead"
    else
        log_error "Failed to create ISO"
        exit 1
    fi
}

# Ensure cleanup on exit
trap cleanup_workspace EXIT

# Run main
main "$@"