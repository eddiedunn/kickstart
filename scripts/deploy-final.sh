#!/bin/bash
#
# Final deployment script for Ubuntu autoinstall VM
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENTOFU_DIR="$PROJECT_ROOT/opentofu"
ISO_PATH="$PROJECT_ROOT/output/ubuntu-22.04-arm64-autoinstall-fixed-20250729-222902.iso"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check ISO exists
if [ ! -f "$ISO_PATH" ]; then
    log_error "ISO not found: $ISO_PATH"
    exit 1
fi

# Update terraform.tfvars
log_info "Updating terraform.tfvars..."
cd "$OPENTOFU_DIR"
sed -i.bak 's|default_iso_path = .*|default_iso_path = "../output/ubuntu-22.04-arm64-autoinstall-fixed-20250729-222902.iso"|' terraform.tfvars

# Set license environment variable
export TF_VAR_parallels_license="6J9TF2-PDPEJY-JHK76N-SNAQKY-7PN7A3"

# Clean up any existing VM
log_info "Cleaning up existing VMs..."
prlctl stop ubuntu-server --kill 2>/dev/null || true
sleep 2
prlctl delete ubuntu-server 2>/dev/null || true

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    log_info "Initializing Terraform..."
    tofu init
fi

# Deploy VM
log_info "Deploying VM with autoinstall ISO..."
tofu apply -auto-approve

# Wait for VM to get IP
log_info "Waiting for VM to complete installation..."
MAX_WAIT=600
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    IP=$(prlctl exec ubuntu-server "ip -4 addr show scope global" 2>/dev/null | awk '/inet/ {gsub(/\/.*/, "", $2); print $2}' | head -1 || true)
    if [ -n "$IP" ]; then
        log_info "VM has IP address: $IP"
        break
    fi
    echo -ne "\rWaiting... $WAITED/$MAX_WAIT seconds"
    sleep 10
    WAITED=$((WAITED + 10))
done

if [ -z "$IP" ]; then
    log_error "VM did not get IP address within timeout"
    exit 1
fi

# Test SSH connection
log_info "Testing SSH connection..."
sleep 30  # Give SSH time to start
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$IP" "echo 'SSH connection successful!' && hostname && uname -a"; then
    echo
    log_info "✓ SUCCESS! VM is running and accessible via SSH"
    echo
    echo "To connect to the VM:"
    echo "  ssh ubuntu@$IP"
    echo
    echo "To destroy the VM:"
    echo "  cd $OPENTOFU_DIR && tofu destroy"
else
    log_error "Failed to connect via SSH"
    echo "Debug info:"
    prlctl list -i ubuntu-server
    exit 1
fi