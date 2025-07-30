#!/bin/bash
#
# Direct VM deployment without Terraform
#

set -euo pipefail

VM_NAME="ubuntu-autoinstall-test"
ISO_PATH="/Users/gdunn6/code/eddiedunn/kickstart/output/ubuntu-22.04-arm64-autoinstall-fixed-20250729-222902.iso"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Clean up any existing VM
log_info "Cleaning up existing VM if any..."
prlctl stop "$VM_NAME" --kill 2>/dev/null || true
prlctl delete "$VM_NAME" 2>/dev/null || true

# Create VM
log_info "Creating VM..."
prlctl create "$VM_NAME" \
    --distribution ubuntu \
    --no-hdd

# Configure VM
log_info "Configuring VM..."
prlctl set "$VM_NAME" \
    --cpus 2 \
    --memsize 4096 \
    --startup-view window \
    --on-shutdown close \
    --time-sync on \
    --efi-boot on

# Add disk
log_info "Adding disk..."
prlctl set "$VM_NAME" \
    --device-add hdd \
    --size 30720

# Configure network
log_info "Configuring network..."
prlctl set "$VM_NAME" \
    --device-set net0 \
    --type shared

# Attach ISO
log_info "Attaching ISO..."
prlctl set "$VM_NAME" \
    --device-set cdrom0 \
    --image "$ISO_PATH" \
    --connect

# Set boot order
prlctl set "$VM_NAME" \
    --device-bootorder "cdrom0 hdd0"

# Start VM
log_info "Starting VM..."
prlctl start "$VM_NAME"

log_info "VM started successfully!"
echo
echo "Monitor installation progress in Parallels Desktop window"
echo "The installation should complete automatically in 5-10 minutes"
echo
echo "To check VM status:"
echo "  prlctl list -i $VM_NAME"
echo
echo "To get IP address (after installation):"
echo "  prlctl exec $VM_NAME 'ip -4 addr show scope global' | grep inet"
echo
echo "To stop and delete:"
echo "  prlctl stop $VM_NAME && prlctl delete $VM_NAME"