# Ubuntu Autoinstall Quick Start Guide

## Prerequisites

- Ubuntu Server ISO (22.04 or later)
- xorriso and perl installed
- Parallels Desktop (for VM deployment)

## Step 1: Build Autoinstall ISO

```bash
./scripts/build-autoinstall-iso.sh path/to/ubuntu-22.04.5-live-server-arm64.iso
```

This creates an autoinstall-enabled ISO in the `output/` directory.

## Step 2: Deploy VM

```bash
./scripts/deploy-vm.sh output/ubuntu-minimal-autoinstall-*.iso my-vm-name
```

## Step 3: Access Your VM

Once installation completes (about 5-10 minutes):

```bash
# Get VM IP address
prlctl exec my-vm-name 'ip addr'

# SSH into the VM
ssh ubuntu@<vm-ip-address>
```

Default password: `ubuntu`

## What Gets Installed

- Ubuntu Server with LVM storage
- OpenSSH server with your SSH keys
- Basic tools: curl, vim
- QEMU guest agent for Parallels integration

## Customization

To modify the autoinstall configuration, edit the user-data section in `scripts/build-autoinstall-iso.sh`.