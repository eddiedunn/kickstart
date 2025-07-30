#!/bin/bash
#
# Prepare VM for template creation
# Cleans and generalizes the VM for reuse
#

set -euo pipefail

# Configuration
VM_NAME="${1:-ubuntu-minimal-test}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Check if VM exists
if ! prlctl list -a | grep -q "$VM_NAME"; then
    log_error "VM '$VM_NAME' not found"
    exit 1
fi

# Start VM if not running
VM_STATUS=$(prlctl list -i "$VM_NAME" | grep "State:" | awk '{print $2}')
if [ "$VM_STATUS" != "running" ]; then
    log_info "Starting VM..."
    prlctl start "$VM_NAME"
    sleep 30  # Wait for boot
fi

log_info "Preparing VM '$VM_NAME' for templating..."

# Execute preparation commands in the VM
log_info "Cleaning package caches..."
prlctl exec "$VM_NAME" sudo apt-get clean
prlctl exec "$VM_NAME" sudo apt-get autoremove -y

log_info "Clearing temporary files..."
prlctl exec "$VM_NAME" sudo rm -rf /tmp/* /var/tmp/*
prlctl exec "$VM_NAME" sudo rm -rf /var/cache/apt/archives/*

log_info "Clearing logs..."
prlctl exec "$VM_NAME" sudo find /var/log -type f -exec truncate -s 0 {} \;

log_info "Removing SSH host keys (will regenerate on first boot)..."
prlctl exec "$VM_NAME" sudo rm -f /etc/ssh/ssh_host_*

log_info "Clearing machine ID (for unique instances)..."
prlctl exec "$VM_NAME" sudo truncate -s 0 /etc/machine-id
prlctl exec "$VM_NAME" sudo rm -f /var/lib/dbus/machine-id

log_info "Clearing cloud-init data..."
prlctl exec "$VM_NAME" sudo cloud-init clean --logs

log_info "Clearing bash history..."
prlctl exec "$VM_NAME" "history -c"
prlctl exec "$VM_NAME" "sudo rm -f /home/ubuntu/.bash_history"
prlctl exec "$VM_NAME" "sudo rm -f /root/.bash_history"

log_info "Clearing network configuration caches..."
prlctl exec "$VM_NAME" sudo rm -f /etc/udev/rules.d/70-persistent-net.rules
prlctl exec "$VM_NAME" "sudo sed -i '/^UUID=/d' /etc/sysconfig/network-scripts/ifcfg-*" 2>/dev/null || true

log_info "Creating regeneration scripts..."
prlctl exec "$VM_NAME" sudo tee /etc/cloud/cloud.cfg.d/99_regenerate.cfg << 'EOF'
#cloud-config
# Regenerate SSH host keys on first boot
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
ssh_deletekeys: false

# Regenerate machine ID
bootcmd:
  - if [ ! -s /etc/machine-id ]; then systemd-machine-id-setup; fi
  - if [ ! -s /var/lib/dbus/machine-id ]; then dbus-uuidgen --ensure; fi
EOF

log_info "Zeroing free space for better compression..."
prlctl exec "$VM_NAME" "sudo dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true"
prlctl exec "$VM_NAME" "sudo rm -f /EMPTY"

log_info "Syncing filesystem..."
prlctl exec "$VM_NAME" sync

log_info "Shutting down VM..."
prlctl exec "$VM_NAME" sudo shutdown -h now

# Wait for VM to stop
log_info "Waiting for VM to stop..."
sleep 5
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if prlctl list -i "$VM_NAME" | grep -q "State: stopped"; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

log_info "✓ VM '$VM_NAME' has been prepared for templating"
echo
echo "Next steps:"
echo "1. Create a template: ./scripts/create-parallels-template.sh $VM_NAME"
echo "2. Or export as PVM: ./scripts/create-parallels-template.sh $VM_NAME --export"