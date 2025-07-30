# Ubuntu VM Deployment Workflow

This repository provides a streamlined workflow for deploying Ubuntu VMs on Parallels Desktop using OpenTofu/Terraform with complete automation.

## Quick Start

### 1. Build an Autoinstall ISO

```bash
# Download an Ubuntu Server ISO first, then:
./scripts/build-autoinstall-iso.sh ubuntu-24.04.2-live-server-arm64.iso

# The script will:
# - Detect ISO version and architecture
# - Let you select SSH keys from ~/.ssh
# - Create an autoinstall ISO with your keys embedded
```

### 2. Configure VMs

Edit `opentofu/terraform.tfvars` to define your VMs:

```hcl
# Single VM (simple mode)
default_iso_path = "../output/ubuntu-24.04-arm64-autoinstall-20250729-123456.iso"

# Or multiple VMs (stack mode)
vm_definitions = {
  "web" = {
    name      = "ubuntu-web"
    cpus      = 2
    memory    = 2048
    disk_size = 20
    iso_path  = "../output/ubuntu-24.04-arm64-autoinstall-20250729-123456.iso"
  }
}
```

### 3. Deploy VMs

```bash
./scripts/deploy-vm.sh

# This will:
# - Initialize OpenTofu/Terraform
# - Show you the deployment plan
# - Create and start VMs
# - Wait for installation to complete
# - Display SSH connection info
```

### 4. Check Status

```bash
# Show VM status and IP addresses
./scripts/status.sh

# Watch mode (updates every 5 seconds)
./scripts/status.sh --watch

# Verbose mode with details
./scripts/status.sh --verbose
```

### 5. Connect to VMs

```bash
# SSH using the IP from status command
ssh ubuntu@<ip-address>

# Your SSH keys are already configured!
```

### 6. Clean Up

```bash
# Destroy VMs only
./scripts/cleanup.sh

# Destroy VMs and remove ISOs
./scripts/cleanup.sh --isos

# Clean everything without confirmation
./scripts/cleanup.sh --all --force
```

## Script Overview

- **build-autoinstall-iso.sh** - Universal ISO builder that works with any Ubuntu Server version
- **deploy-vm.sh** - Wrapper for OpenTofu/Terraform deployment with validation
- **validate-config.sh** - Validates autoinstall configurations for syntax and security
- **status.sh** - Shows VM status, IPs, and SSH commands
- **cleanup.sh** - Safely destroys VMs and optionally removes ISOs

## Features

- ✅ Completely hands-free Ubuntu installation
- ✅ Automatic SSH key embedding
- ✅ Support for multiple VM deployments
- ✅ Headless operation (no GUI required)
- ✅ Works with any Ubuntu Server ISO
- ✅ Network configuration via DHCP
- ✅ Automatic detection of ISO version and architecture

## Requirements

- macOS with Apple Silicon or Intel
- Parallels Desktop
- OpenTofu (`brew install opentofu`) or Terraform
- SSH keys in ~/.ssh/

## Troubleshooting

### VMs don't get IP addresses
- Wait a few minutes for installation to complete
- Check with `./scripts/status.sh --watch`
- Ensure your Parallels network settings allow DHCP

### ISO build fails
- Ensure you have `xorriso` installed: `brew install xorriso`
- Check that the input ISO is a valid Ubuntu Server ISO
- Verify you have SSH keys in ~/.ssh/

### Deployment fails
- Check `opentofu/terraform.tfvars` has valid ISO paths
- Ensure Parallels Desktop is running
- Try `cd opentofu && tofu init` to reinitialize

## Advanced Usage

### Multi-VM Stacks

Define complex environments in `terraform.tfvars`:

```hcl
vm_definitions = {
  "web" = {
    name        = "web-server"
    cpus        = 2
    memory      = 2048
    disk_size   = 20
    iso_path    = "../output/ubuntu-autoinstall.iso"
    start_after = []
  },
  "db" = {
    name        = "database"
    cpus        = 4
    memory      = 8192
    disk_size   = 100
    iso_path    = "../output/ubuntu-autoinstall.iso"
    start_after = []
  },
  "cache" = {
    name        = "redis-cache"
    cpus        = 2
    memory      = 4096
    disk_size   = 20
    iso_path    = "../output/ubuntu-autoinstall.iso"
    start_after = ["db"]  # Start after database VM
  }
}
```

### Headless vs GUI Mode

```hcl
# Run VMs without GUI (default)
headless = true

# Show VM console windows
headless = false
```