#!/bin/bash
#
# prepare-vm-template.sh - Prepare VM for Template Creation
#
# PURPOSE:
#   Generalizes a VM by removing machine-specific data and cleaning caches.
#   This ensures each clone from the template gets unique identifiers.
#   Essential step before converting any VM to a template.
#
# USAGE:
#   ./prepare-vm-template.sh <vm-name>
#
# PARAMETERS:
#   $1 - Name of the VM to prepare (default: ubuntu-minimal-test)
#        VM must exist in Parallels Desktop
#
# WHAT IT DOES:
#   1. Package Management:
#      - Cleans APT package caches (apt-get clean)
#      - Removes orphaned packages (autoremove)
#      - Frees up significant disk space
#   
#   2. System Cleanup:
#      - Removes all temporary files (/tmp/*, /var/tmp/*)
#      - Truncates all log files while preserving structure
#      - Clears bash history for all users
#   
#   3. Machine Identity:
#      - Deletes SSH host keys (regenerated on first boot)
#      - Clears machine-id (SystemD identifier)
#      - Removes D-Bus machine ID
#      - Removes network interface MAC bindings
#   
#   4. Cloud-Init Reset:
#      - Runs 'cloud-init clean' to reset state
#      - Ensures cloud-init runs fresh on each clone
#      - Creates config for SSH key regeneration
#   
#   5. Disk Optimization:
#      - Zeros free disk space for better compression
#      - Improves template export/compression ratios
#      - Reduces storage requirements
#
# EXAMPLE:
#   # Prepare a single VM
#   ./prepare-vm-template.sh my-ubuntu-vm
#   
#   # Prepare with custom name
#   ./prepare-vm-template.sh production-base
#
# WORKFLOW:
#   1. Script checks if VM exists
#   2. Starts VM if not already running
#   3. Executes all cleanup operations via prlctl exec
#   4. Creates cloud-init regeneration config
#   5. Zeros free space for compression
#   6. Gracefully shuts down the VM
#   7. Waits for complete shutdown
#
# SECURITY IMPLICATIONS:
#   - SSH host keys are removed (prevents key reuse)
#   - Machine IDs are cleared (ensures uniqueness)
#   - Command history is erased (removes sensitive data)
#   - Network configs are reset (prevents conflicts)
#
# NOTES:
#   - VM must exist in Parallels Desktop
#   - Requires sudo access inside the VM
#   - Takes 2-5 minutes depending on VM size
#   - VM will be shutdown after preparation
#   - Safe to run multiple times
#
# NEXT STEPS:
#   After preparation completes:
#   1. Create template: ./create-parallels-template.sh <vm-name>
#   2. Or use: ./manage-templates.sh create <vm-name>
#
# TROUBLESHOOTING:
#   - "VM not found": Check VM name with 'prlctl list -a'
#   - "Permission denied": Ensure VM has sudo configured
#   - "Timeout waiting": VM may have shutdown issues
#   - "Command failed": Check VM has required commands
#

set -euo pipefail

# Configuration
VM_NAME="${1:-ubuntu-minimal-test}"  # Default VM name if not specified

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
# Step 1: Clean package manager caches
log_info "Cleaning package caches..."
prlctl exec "$VM_NAME" sudo apt-get clean          # Remove downloaded packages
prlctl exec "$VM_NAME" sudo apt-get autoremove -y  # Remove orphaned packages

# Step 2: Clear temporary files
log_info "Clearing temporary files..."
prlctl exec "$VM_NAME" sudo rm -rf /tmp/* /var/tmp/*         # System temp files
prlctl exec "$VM_NAME" sudo rm -rf /var/cache/apt/archives/* # APT cache

# Step 3: Clear all log files (keep structure, empty contents)
log_info "Clearing logs..."
prlctl exec "$VM_NAME" sudo find /var/log -type f -exec truncate -s 0 {} \;

# Step 4: Remove SSH host keys
# These will be regenerated on first boot, ensuring each clone is unique
log_info "Removing SSH host keys (will regenerate on first boot)..."
prlctl exec "$VM_NAME" sudo rm -f /etc/ssh/ssh_host_*

# Step 5: Clear machine IDs
# Each clone needs unique IDs for proper system identification
log_info "Clearing machine ID (for unique instances)..."
prlctl exec "$VM_NAME" sudo truncate -s 0 /etc/machine-id    # SystemD machine ID
prlctl exec "$VM_NAME" sudo rm -f /var/lib/dbus/machine-id   # D-Bus machine ID

# Step 6: Reset cloud-init
# Ensures cloud-init runs fresh on each clone
log_info "Clearing cloud-init data..."
prlctl exec "$VM_NAME" sudo cloud-init clean --logs

# Step 7: Clear command history for security
log_info "Clearing bash history..."
prlctl exec "$VM_NAME" "history -c"                           # Current session
prlctl exec "$VM_NAME" "sudo rm -f /home/ubuntu/.bash_history" # User history
prlctl exec "$VM_NAME" "sudo rm -f /root/.bash_history"       # Root history

# Step 8: Clear network configuration caches
log_info "Clearing network configuration caches..."
# Remove persistent network rules that bind to MAC addresses
prlctl exec "$VM_NAME" sudo rm -f /etc/udev/rules.d/70-persistent-net.rules
# Remove interface UUIDs (mainly for RHEL-based systems)
prlctl exec "$VM_NAME" "sudo sed -i '/^UUID=/d' /etc/sysconfig/network-scripts/ifcfg-*" 2>/dev/null || true

# Step 9: Create cloud-init configuration for first boot
# This ensures SSH keys and machine IDs are regenerated
log_info "Creating regeneration scripts..."
prlctl exec "$VM_NAME" sudo tee /etc/cloud/cloud.cfg.d/99_regenerate.cfg << 'EOF'
#cloud-config
# Regenerate SSH host keys on first boot
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']  # Key types to generate
ssh_deletekeys: false                          # Don't delete (they're already gone)

# Regenerate machine ID
bootcmd:
  - if [ ! -s /etc/machine-id ]; then systemd-machine-id-setup; fi     # SystemD ID
  - if [ ! -s /var/lib/dbus/machine-id ]; then dbus-uuidgen --ensure; fi # D-Bus ID
EOF

# Step 10: Zero free disk space
# This improves compression ratios when exporting templates
log_info "Zeroing free space for better compression..."
prlctl exec "$VM_NAME" "sudo dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true"
prlctl exec "$VM_NAME" "sudo rm -f /EMPTY"

log_info "Syncing filesystem..."
prlctl exec "$VM_NAME" sync

log_info "Shutting down VM..."
prlctl exec "$VM_NAME" sudo shutdown -h now

# Wait for VM to stop gracefully
log_info "Waiting for VM to stop..."
sleep 5
MAX_WAIT=60  # Maximum 60 seconds to wait
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