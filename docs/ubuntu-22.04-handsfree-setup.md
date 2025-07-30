# Ubuntu 22.04 Hands-Free Installation with OpenTofu/Terraform

This guide provides a complete hands-free installation setup for Ubuntu 22.04 LTS using Kickstart/cloud-init with OpenTofu (or Terraform) and Parallels Desktop.

## Overview

The setup consists of:
1. An autoinstall configuration that requires zero interaction
2. A custom ISO with embedded autoinstall configuration
3. OpenTofu/Terraform configuration for Parallels Desktop VM creation
4. Automatic provisioning with cloud-init after installation

## Prerequisites

- macOS with Parallels Desktop installed
- OpenTofu or Terraform installed
- Ubuntu 22.04 LTS Server ISO (ARM64 for Apple Silicon)
- xorriso for ISO manipulation: `brew install xorriso`

## Quick Start

### 1. Build the Autoinstall ISO

```bash
# Download Ubuntu 22.04 LTS Server ISO if you haven't already
# From: https://cdimage.ubuntu.com/releases/22.04/release/

# Build the custom autoinstall ISO
./scripts/build-ubuntu-22.04-autoinstall.sh /path/to/ubuntu-22.04.5-live-server-arm64.iso
```

This creates an ISO at `output/ubuntu-22.04-autoinstall-arm64.iso` with:
- Automatic boot (1 second timeout)
- No user prompts during installation
- Minimal package selection for fast installation
- Ready for cloud-init configuration

### 2. Configure OpenTofu/Terraform

```bash
cd opentofu

# Copy and edit the example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and add your SSH public key
vim terraform.tfvars
```

### 3. Create the VM

```bash
# Initialize Tofu/Terraform
tofu init  # or: terraform init

# Review the plan
tofu plan

# Create the VM (completely hands-free!)
tofu apply
```

The VM will:
1. Boot from the custom ISO automatically
2. Install Ubuntu 22.04 without any prompts
3. Reboot when complete
4. Configure itself with cloud-init
5. Be ready for SSH access

### 4. Connect to the VM

```bash
# Get the VM's IP address
prlctl list -f | grep ubuntu-22-auto

# SSH to the VM
ssh ubuntu@<ip-address>
```

## How It Works

### Autoinstall Configuration

The `configs/ubuntu-22.04-handsfree.yaml` file contains:
- Complete automation with `interactive-sections: []`
- Network configuration using DHCP
- Storage configuration using LVM on the entire disk
- Temporary installer user (removed after installation)
- SSH server with key-only authentication
- Minimal package selection for speed

### ISO Building

The build script:
1. Extracts the original Ubuntu ISO
2. Adds the autoinstall configuration to `/nocloud/`
3. Modifies GRUB to automatically boot with autoinstall parameters
4. Rebuilds the ISO with proper boot configuration

### OpenTofu/Terraform Configuration

The Terraform configuration:
1. Creates a Parallels Desktop VM from the custom ISO
2. Configures hardware (CPU, memory, disk)
3. Sets up networking
4. Waits for installation to complete
5. Provides connection information

### Cloud-Init Integration

After the autoinstall completes:
1. The system reboots
2. Cloud-init runs with configuration from Terraform
3. Creates the ubuntu user with SSH key
4. Installs additional packages
5. Configures the system

## Customization

### Modify Installation Settings

Edit `configs/ubuntu-22.04-handsfree.yaml`:
- Change network configuration
- Modify storage layout
- Add/remove packages
- Configure different users

### Adjust VM Hardware

Edit `terraform.tfvars`:
```hcl
vm_cpus      = 4      # More CPUs
vm_memory    = 8192   # 8GB RAM
vm_disk_size = 100    # 100GB disk
```

### Add Post-Installation Tasks

In the Terraform configuration, modify the `cloud_init_config` local:
```hcl
runcmd = [
  # Your custom commands here
  "apt-get install -y docker.io",
  "usermod -aG docker ubuntu"
]
```

## Troubleshooting

### Installation Hangs

If the installation stops at any prompt:
1. The autoinstall configuration may have an error
2. Check the VM console in Parallels Desktop
3. Validate the config: `cloud-init devel schema --config-file configs/ubuntu-22.04-handsfree.yaml`

### VM Doesn't Boot

1. Ensure the ISO was built successfully
2. Check that the ISO contains `/nocloud/user-data`
3. Verify GRUB was modified correctly

### Can't SSH to VM

1. Wait for installation to complete (5-10 minutes)
2. Check VM IP: `prlctl list -f`
3. Ensure your SSH key is correct in terraform.tfvars
4. Check VM console for errors

### Build Script Fails

1. Ensure xorriso is installed: `brew install xorriso`
2. Check that the input ISO path is correct
3. Ensure you have write permissions to the output directory

## Advanced Usage

### Multiple VMs

Create multiple VM configurations:
```bash
# Create different .tfvars files
cp terraform.tfvars vm1.tfvars
cp terraform.tfvars vm2.tfvars

# Deploy multiple VMs
tofu apply -var-file=vm1.tfvars -state=vm1.tfstate
tofu apply -var-file=vm2.tfvars -state=vm2.tfstate
```

### Custom Network Configuration

For static IP configuration, modify the autoinstall:
```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      addresses: [192.168.1.100/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

### Integration with CI/CD

The hands-free nature makes this perfect for CI/CD:
```bash
# In your CI pipeline
./scripts/build-ubuntu-22.04-autoinstall.sh $ISO_PATH
cd opentofu
tofu init
tofu apply -auto-approve -var="ssh_public_key=$CI_SSH_KEY"
```

## Security Considerations

1. The autoinstall ISO contains a temporary password - ensure it's not distributed
2. SSH key authentication is enforced - password auth is disabled
3. The temporary installer user is removed after installation
4. Consider encrypting the disk in production environments

## Next Steps

1. Customize the autoinstall configuration for your needs
2. Add monitoring and logging
3. Integrate with configuration management (Ansible, etc.)
4. Set up automated testing of your installations