#!/bin/bash
#
# deploy-vm.sh - Deploy Ubuntu VM from Autoinstall ISO
#
# PURPOSE:
#   Creates and starts a new Parallels Desktop VM using a custom autoinstall ISO.
#   This script provides a quick way to deploy VMs without using OpenTofu/Terraform.
#   Ideal for testing, development, or when you need a single VM quickly.
#
# USAGE:
#   ./deploy-vm.sh <autoinstall-iso-path> [vm-name]
#
# PARAMETERS:
#   $1 - Path to autoinstall ISO (required)
#        Can be absolute or relative path
#        Must be created with build-autoinstall-iso.sh
#   $2 - VM name (optional, default: ubuntu-autoinstall)
#        Must be unique in Parallels Desktop
#
# EXAMPLES:
#   # Deploy with auto-generated name
#   ./deploy-vm.sh output/ubuntu-autoinstall.iso
#   
#   # Deploy with custom name
#   ./deploy-vm.sh output/ubuntu-autoinstall.iso my-ubuntu-vm
#   
#   # Deploy using relative path
#   ./deploy-vm.sh ../output/ubuntu-minimal-autoinstall-20240315.iso web-server
#
# VM SPECIFICATIONS:
#   - CPUs: 2 cores
#   - Memory: 4GB (4096 MB)
#   - Disk: 20GB (thin provisioned)
#   - Network: Shared (NAT with DHCP)
#   - Display: Window mode (visible GUI)
#   - Firmware: EFI boot (required for Ubuntu 22.04+)
#   - Architecture: Automatically detected (ARM64/x86_64)
#
# WORKFLOW:
#   1. Validates ISO file exists
#   2. Removes any existing VM with same name
#   3. Creates new VM with specified configuration
#   4. Attaches autoinstall ISO as boot device
#   5. Starts VM and begins unattended installation
#   6. Displays helpful post-deployment commands
#
# POST-DEPLOYMENT:
#   - Installation takes 5-10 minutes (varies by hardware)
#   - VM auto-reboots after installation completes
#   - Default credentials: ubuntu/ubuntu (if no SSH keys)
#   - SSH available on DHCP-assigned IP address
#
# NOTES:
#   - Existing VM with same name is forcefully removed
#   - VM window shows installation progress
#   - Network uses Parallels Shared mode (NAT)
#   - Disk grows dynamically up to 20GB limit
#   - EFI boot required for modern Ubuntu versions
#
# TROUBLESHOOTING:
#   - "ISO not found": Check file path and permissions
#   - "VM already exists": Script auto-removes, but check if stuck
#   - "Network timeout": Verify Parallels network settings
#   - "Boot failure": Ensure ISO was created for correct architecture
#
# SEE ALSO:
#   - scripts/build-autoinstall-iso.sh: Create custom ISOs
#   - scripts/status.sh: Monitor VM deployment status
#   - scripts/manage-templates.sh: Create templates from VMs
#

set -euo pipefail

# Script parameters
ISO_PATH="${1:-}"                    # Path to autoinstall ISO
VM_NAME="${2:-ubuntu-autoinstall}"   # VM name with default

if [ -z "$ISO_PATH" ] || [ ! -f "$ISO_PATH" ]; then
    echo "Usage: $0 <autoinstall-iso-path> [VM_NAME]"
    echo "Example: $0 output/ubuntu-autoinstall.iso my-ubuntu-vm"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Clean up any existing VM with the same name
# This ensures a fresh deployment every time
# The --kill flag forces immediate shutdown (no graceful shutdown)
# stderr redirected to null to suppress errors if VM doesn't exist
prlctl stop "$VM_NAME" --kill 2>/dev/null || true
prlctl delete "$VM_NAME" 2>/dev/null || true

# Create and configure VM
log_info "Creating VM..."

# Create base VM without disk (we'll add it separately)
# --distribution ubuntu: Sets OS type for optimal Parallels configuration
# --no-hdd: Don't create default disk (we'll add custom size)
prlctl create "$VM_NAME" --distribution ubuntu --no-hdd

# Configure hardware specifications
# These settings can be adjusted based on your needs and available resources
prlctl set "$VM_NAME" \
    --cpus 2 \              # Number of CPU cores
    --memsize 4096 \        # RAM in MB (4GB)
    --startup-view window \ # Show VM window (use 'headless' for no display)
    --efi-boot on           # Enable EFI firmware (required for Ubuntu 22.04+)

# Add storage
# Size is in MB (20480 MB = 20 GB)
# Disk will be thin-provisioned (grows as needed)
prlctl set "$VM_NAME" --device-add hdd --size 20480  # 20GB disk

# Configure network adapter
# Network types:
#   - shared: NAT with host (default, good for internet access)
#   - bridged: Direct connection to physical network
#   - host-only: Isolated network with host access only
prlctl set "$VM_NAME" --device-set net0 --type shared

# Attach installation ISO
# --connect: Ensures the ISO is connected at boot
prlctl set "$VM_NAME" --device-set cdrom0 --image "$ISO_PATH" --connect

# Set boot order to boot from ISO first
# After installation, you may want to change this to "hdd0 cdrom0"
prlctl set "$VM_NAME" --device-bootorder "cdrom0 hdd0"

# Start VM
log_info "Starting VM..."
prlctl start "$VM_NAME"

log_info "VM started! Monitor progress in Parallels window."
echo
echo "Useful commands:"
echo "  Check status:  prlctl list -i $VM_NAME"
echo "  Get IP:        prlctl exec $VM_NAME 'ip addr' 2>/dev/null || echo 'Not ready'"
echo "  SSH access:    ssh ubuntu@<VM-IP>"
echo "  Stop VM:       prlctl stop $VM_NAME"
echo "  Delete VM:     prlctl delete $VM_NAME"
echo
echo "Installation typically takes 5-10 minutes depending on your hardware."
echo
echo "The autoinstall will:"
echo "  - Configure Ubuntu with DHCP networking"
echo "  - Create user 'ubuntu' with your SSH keys"
echo "  - Install SSH server and essential tools"
echo "  - Reboot when complete"