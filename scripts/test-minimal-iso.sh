#!/bin/bash
#
# Test minimal autoinstall ISO
#

set -euo pipefail

VM_NAME="ubuntu-minimal-test"
ISO_PATH="/Users/gdunn6/code/eddiedunn/kickstart/output/ubuntu-minimal-autoinstall-20250729-224141.iso"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Clean up
prlctl stop "$VM_NAME" --kill 2>/dev/null || true
prlctl delete "$VM_NAME" 2>/dev/null || true

# Create and configure VM
log_info "Creating VM..."
prlctl create "$VM_NAME" --distribution ubuntu --no-hdd
prlctl set "$VM_NAME" --cpus 2 --memsize 4096 --startup-view window --efi-boot on
prlctl set "$VM_NAME" --device-add hdd --size 20480
prlctl set "$VM_NAME" --device-set net0 --type shared
prlctl set "$VM_NAME" --device-set cdrom0 --image "$ISO_PATH" --connect
prlctl set "$VM_NAME" --device-bootorder "cdrom0 hdd0"

# Start VM
log_info "Starting VM..."
prlctl start "$VM_NAME"

log_info "VM started! Monitor progress in Parallels window."
echo
echo "Check status with: prlctl list -i $VM_NAME"
echo "Check IP with: prlctl exec $VM_NAME 'ip addr' 2>/dev/null || echo 'Not ready'"