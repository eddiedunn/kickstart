#!/bin/bash
#
# Universal Ubuntu Autoinstall ISO Builder
# Supports any Ubuntu Server ISO version with automatic SSH key embedding
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

detect_iso_version() {
    local iso_path="$1"
    local volume_id=$(xorriso -indev "$iso_path" -pvd_info 2>&1 | grep "Volume Id" | cut -d: -f2 | xargs || echo "")
    
    # Extract version from volume ID or filename
    if [[ "$volume_id" =~ ([0-9]+\.[0-9]+) ]] || [[ "$iso_path" =~ ([0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

detect_architecture() {
    local iso_path="$1"
    if [[ "$iso_path" =~ (amd64|x86_64) ]]; then
        echo "amd64"
    elif [[ "$iso_path" =~ (arm64|aarch64) ]]; then
        echo "arm64"
    else
        # Try to detect from ISO contents
        local arch=$(xorriso -indev "$iso_path" -find /casper -name "vmlinuz*" 2>/dev/null | head -1)
        if [[ "$arch" =~ arm64 ]]; then
            echo "arm64"
        else
            echo "amd64"
        fi
    fi
}

select_ssh_keys() {
    local selected_keys=()
    
    # Find all SSH public keys
    local ssh_keys=()
    for key in "$HOME"/.ssh/*.pub; do
        [ -f "$key" ] && ssh_keys+=("$key")
    done
    
    if [ ${#ssh_keys[@]} -eq 0 ]; then
        log_warn "No SSH public keys found in ~/.ssh"
        log_info "Generate one with: ssh-keygen -t ed25519"
        return 1
    fi
    
    # If only one key, use it automatically
    if [ ${#ssh_keys[@]} -eq 1 ]; then
        selected_keys=("${ssh_keys[@]}")
        log_info "Using SSH key: $(basename "${ssh_keys[0]}")"
    else
        # Display available keys
        echo
        log_info "Found ${#ssh_keys[@]} SSH key(s):"
        for i in "${!ssh_keys[@]}"; do
            local key_file="${ssh_keys[$i]}"
            local key_info=$(ssh-keygen -l -f "$key_file" 2>/dev/null || echo "Unknown key")
            echo -e "${BLUE}[$((i+1))]${NC} $(basename "$key_file"): $key_info"
        done
        
        echo
        echo "Select keys to include (e.g., '1' or '1 3' or 'all') [default: all]:"
        read -r selection
        
        # Default to all if empty
        [ -z "$selection" ] && selection="all"
        
        if [ "$selection" = "all" ]; then
            selected_keys=("${ssh_keys[@]}")
        else
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#ssh_keys[@]}" ]; then
                    selected_keys+=("${ssh_keys[$((num-1))]}")
                fi
            done
        fi
    fi
    
    # Return selected keys
    printf '%s\n' "${selected_keys[@]}"
}

create_autoinstall_config() {
    local output_file="$1"
    shift
    local ssh_keys=("$@")
    
    # Detect if we're building for ARM64
    local arch="${DETECTED_ARCH:-amd64}"
    
    cat > "$output_file" << 'EOF'
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  
  locale: en_US.UTF-8
  keyboard:
    layout: us
    variant: ""
  
  network:
    version: 2
    ethernets:
      enp0s5:  # Parallels default (works on both architectures)
        dhcp4: true
        dhcp6: false
        optional: true
      eth0:    # Common ARM64 interface name
        dhcp4: true
        dhcp6: false
        optional: true
      enp0s3:  # VirtualBox default (x86)
        dhcp4: true
        dhcp6: false
        optional: true
      ens160:  # VMware on ARM64
        dhcp4: true
        dhcp6: false
        optional: true
      ens33:   # VMware default (x86)
        dhcp4: true
        dhcp6: false
        optional: true
  
  storage:
    layout:
      name: lvm
      sizing-policy: all
  
  identity:
    hostname: ubuntu-server
    username: ubuntu
    # Password 'ubuntu' - required for initial setup
    password: "$6$rounds=4096$8dkK1P/oE$2DGKKt0wLlTVJ7USY.0jN9du8FetmEr51yjPyeiR.zKE3DGFcitNL/nF1l62BLJNR87lQZixObuXYny.Mf17K1"
  
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
EOF

    # Add SSH keys if provided
    if [ ${#ssh_keys[@]} -gt 0 ]; then
        for key_file in "${ssh_keys[@]}"; do
            echo "      - \"$(cat "$key_file")\"" >> "$output_file"
        done
    else
        # If no keys provided, add empty list
        echo "      []" >> "$output_file"
    fi
    
    cat >> "$output_file" << 'EOF'
  
  packages:
    - qemu-guest-agent
    - cloud-init
    - openssh-server
    - curl
    - wget
    - vim
    - net-tools
    - htop
    - jq
  
  updates: security
  
  late-commands:
    # Ensure proper SSH directory permissions
    - curtin in-target --target=/target -- mkdir -p /home/ubuntu/.ssh
    - curtin in-target --target=/target -- chmod 700 /home/ubuntu/.ssh
    - curtin in-target --target=/target -- chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    # Enable services
    - curtin in-target --target=/target -- systemctl enable ssh || true
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent || true
    # Remove cloud-init default network config to prevent conflicts
    - rm -f /target/etc/cloud/cloud.cfg.d/50-curtin-networking.cfg || true
    - rm -f /target/etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg || true
  
  user-data:
    disable_root: true
    ssh_pwauth: false
  
  shutdown: reboot
EOF
}

update_boot_config() {
    local work_dir="$1"
    local arch="$2"
    
    log_info "Updating boot configuration for $arch..."
    
    # Find and update all GRUB configuration files
    find "$work_dir" -name "grub.cfg" -type f | while read -r grub_file; do
        log_info "Updating $(basename "$(dirname "$grub_file")")/grub.cfg"
        
        # Add autoinstall parameters to kernel command line
        perl -pi -e 's|(linux\s+/casper/vmlinuz[^\s]*)\s+(.*?)(\s+---)|\1 \2 autoinstall ds=nocloud\;s=/cdrom/nocloud/\3|g' "$grub_file"
        perl -pi -e 's|(linux\s+/casper/hwe-vmlinuz[^\s]*)\s+(.*?)(\s+---)|\1 \2 autoinstall ds=nocloud\;s=/cdrom/nocloud/\3|g' "$grub_file"
        
        # Reduce timeout for faster boot
        perl -pi -e 's|timeout=[0-9]+|timeout=1|g' "$grub_file"
        
        # Set default menu entry
        perl -pi -e 's|set default="[0-9]+"|set default="0"|g' "$grub_file"
    done
}

build_iso() {
    local input_iso="$1"
    local output_iso="$2"
    local work_dir="$3"
    local arch="$4"
    
    cd "$work_dir"
    
    # Get volume ID from original ISO
    local volume_id=$(xorriso -indev "$input_iso" -pvd_info 2>&1 | grep "Volume Id" | cut -d: -f2 | xargs || echo "Ubuntu-Server")
    
    log_info "Building ISO for $arch architecture..."
    
    # Try to extract mkisofs parameters from original ISO
    if xorriso -indev "$input_iso" -report_el_torito as_mkisofs 2>/dev/null > mkisofs.opts; then
        # Use original boot configuration
        log_info "Using original ISO boot configuration"
        # Truncate volume ID if too long (max 32 chars)
        local vol_label="${volume_id}-Autoinstall"
        if [ ${#vol_label} -gt 32 ]; then
            vol_label="${volume_id:0:20}-Autoinstall"
        fi
        
        eval xorriso -as mkisofs \
            -r \
            -V "'$vol_label'" \
            -o "'$output_iso'" \
            $(grep -v "^-V" mkisofs.opts | tr '\n' ' ') \
            . 2>&1 || {
            log_warn "Failed with original options, using fallback"
            build_iso_fallback "$output_iso" "$volume_id" "$arch"
        }
    else
        build_iso_fallback "$output_iso" "$volume_id" "$arch"
    fi
}

build_iso_fallback() {
    local output_iso="$1"
    local volume_id="$2"
    local arch="$3"
    
    # Truncate volume ID if too long (max 32 chars)
    local vol_label="${volume_id}-Autoinstall"
    if [ ${#vol_label} -gt 32 ]; then
        vol_label="${volume_id:0:20}-Autoinstall"
    fi
    
    if [ "$arch" = "amd64" ]; then
        xorriso -as mkisofs \
            -r \
            -V "$vol_label" \
            -o "$output_iso" \
            -J -joliet-long \
            -l \
            -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -eltorito-alt-boot \
            -e boot/grub/efi.img \
            -no-emul-boot \
            .
    else
        # ARM64 doesn't use legacy BIOS boot
        xorriso -as mkisofs \
            -r \
            -V "$vol_label" \
            -o "$output_iso" \
            -J -joliet-long \
            -l \
            .
    fi
}

# Main function
main() {
    local input_iso="${1:-}"
    
    echo
    echo -e "${GREEN}Universal Ubuntu Autoinstall ISO Builder${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo
    
    # Validate input
    if [ -z "$input_iso" ] || [ ! -f "$input_iso" ]; then
        echo "Usage: $0 <ubuntu-server-iso>"
        echo
        echo "Examples:"
        echo "  $0 ubuntu-22.04.5-live-server-amd64.iso"
        echo "  $0 ubuntu-24.04.2-live-server-arm64.iso"
        echo "  $0 /path/to/ubuntu-server.iso"
        echo
        echo "This script will:"
        echo "  1. Detect ISO version and architecture"
        echo "  2. Select SSH keys from ~/.ssh"
        echo "  3. Create autoinstall configuration"
        echo "  4. Build a new ISO with embedded config"
        echo "  5. Output ready-to-use ISO for OpenTofu/Parallels"
        exit 1
    fi
    
    # Convert to absolute path
    input_iso=$(cd "$(dirname "$input_iso")" && pwd)/$(basename "$input_iso")
    
    # Detect ISO properties
    local version=$(detect_iso_version "$input_iso")
    local arch=$(detect_architecture "$input_iso")
    
    log_info "Detected Ubuntu $version $arch"
    
    # Select SSH keys
    log_info "Selecting SSH keys..."
    local ssh_keys=()
    if selected=$(select_ssh_keys); then
        # Use a more portable method instead of mapfile
        while IFS= read -r key; do
            [ -n "$key" ] && ssh_keys+=("$key")
        done <<< "$selected"
        log_info "Selected ${#ssh_keys[@]} SSH key(s)"
    else
        log_error "No SSH keys available. Exiting."
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
    log_info "Creating autoinstall configuration..."
    mkdir -p nocloud
    DETECTED_ARCH="$arch" create_autoinstall_config "nocloud/user-data" "${ssh_keys[@]}"
    
    # Create meta-data
    cat > nocloud/meta-data << EOF
instance-id: ubuntu-autoinstall-$(date +%s)
local-hostname: ubuntu-server
EOF
    
    # Update boot configuration
    update_boot_config "$WORK_DIR" "$arch"
    
    # Build ISO
    local iso_name="ubuntu-${version}-${arch}-autoinstall-$(date +%Y%m%d-%H%M%S).iso"
    local output_iso="${OUTPUT_DIR}/${iso_name}"
    
    log_info "Building autoinstall ISO..."
    build_iso "$input_iso" "$output_iso" "$WORK_DIR" "$arch"
    
    # Cleanup
    cd "$PROJECT_ROOT"
    cleanup_workspace
    
    # Verify and report
    if [ -f "$output_iso" ]; then
        local iso_size=$(du -h "$output_iso" | cut -f1)
        
        echo
        log_info "✓ ISO created successfully!"
        echo
        echo -e "${GREEN}Output ISO:${NC} $output_iso"
        echo -e "${GREEN}Size:${NC} $iso_size"
        echo -e "${GREEN}Version:${NC} Ubuntu $version $arch"
        echo -e "${GREEN}SSH Keys:${NC} ${#ssh_keys[@]} embedded"
        echo
        echo "This ISO will:"
        echo "  • Install Ubuntu completely hands-free"
        echo "  • Create user 'ubuntu' with sudo access"
        echo "  • Configure SSH with your embedded keys"
        echo "  • Disable password authentication"
        echo "  • Configure network via DHCP"
        echo
        echo "To use with OpenTofu:"
        echo "  1. Update terraform.tfvars:"
        echo "     custom_iso_path = \"$output_iso\""
        echo "  2. Run: ./scripts/deploy-vm.sh"
    else
        log_error "Failed to create ISO"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_workspace EXIT

# Run main
main "$@"