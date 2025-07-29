#!/bin/bash
#
# Inject cloud-init configuration into Parallels VM
# This script creates an ISO with cloud-init data that can be attached to the VM
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${PROJECT_ROOT}/work/cloud-init"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# Parameters
VM_NAME="${1:-}"
HOSTNAME="${2:-ubuntu}"
SSH_KEY="${3:-}"

# Validate parameters
if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm_name> <hostname> <ssh_public_key>"
    echo "Example: $0 ubuntu-vm ubuntu-server 'ssh-rsa AAAAB3...'"
    exit 1
fi

# Create work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# Create meta-data
cat > "$WORK_DIR/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${HOSTNAME}
EOF

# Create user-data
cat > "$WORK_DIR/user-data" << EOF
#cloud-config
hostname: ${HOSTNAME}
fqdn: ${HOSTNAME}.local
manage_etc_hosts: true

users:
  - name: ubuntu
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    lock_passwd: true
EOF

# Add SSH key if provided
if [ -n "$SSH_KEY" ]; then
    cat >> "$WORK_DIR/user-data" << EOF
    ssh_authorized_keys:
      - ${SSH_KEY}
EOF
fi

# Continue user-data
cat >> "$WORK_DIR/user-data" << EOF

# Configure SSH
ssh_pwauth: false
disable_root: true

# Update packages
package_update: true
package_upgrade: false

# Install additional packages
packages:
  - qemu-guest-agent
  - net-tools
  - curl
  - wget
  - htop
  - jq

# Configure system
timezone: UTC
locale: en_US.UTF-8

# Run commands
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "Provisioned by cloud-init on \$(date)" > /etc/motd

# Power state
power_state:
  mode: reboot
  timeout: 30
  condition: true

# Final message
final_message: "Cloud-init configuration complete for ${HOSTNAME}"
EOF

# Create cloud-init ISO
echo "Creating cloud-init ISO..."
cd "$WORK_DIR"

# Use mkisofs to create the ISO (compatible with cloud-init NoCloud datasource)
mkisofs -output "${OUTPUT_DIR}/cloud-init-${VM_NAME}.iso" \
    -volid cidata \
    -joliet \
    -rock \
    -input-charset utf-8 \
    user-data meta-data

echo "Cloud-init ISO created: ${OUTPUT_DIR}/cloud-init-${VM_NAME}.iso"
echo ""
echo "To use this ISO with Parallels:"
echo "1. Attach it as a CD-ROM to your VM:"
echo "   prlctl set ${VM_NAME} --device-add cdrom --image ${OUTPUT_DIR}/cloud-init-${VM_NAME}.iso"
echo ""
echo "2. Or during VM creation:"
echo "   prlctl create ${VM_NAME} --ostype ubuntu"
echo "   prlctl set ${VM_NAME} --device-add cdrom --image ${OUTPUT_DIR}/cloud-init-${VM_NAME}.iso"
echo ""
echo "3. Start the VM and cloud-init will configure it automatically"