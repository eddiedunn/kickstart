# Ubuntu 22.04 Hands-Free Installation for Parallels on Mac (ARM64)

This guide provides a complete solution for creating hands-free Ubuntu 22.04 installations on Parallels Desktop for Mac with ARM64 architecture, integrated with OpenTofu for infrastructure as code.

## Overview

The solution consists of:
1. **Autoinstall Configuration**: Cloud-init based configuration for unattended installation
2. **Custom ISO Builder**: Script to embed autoinstall into Ubuntu ISO
3. **Cloud-Init Integration**: Dynamic configuration for hostname and SSH keys
4. **OpenTofu Module**: Infrastructure as code for VM provisioning

## Prerequisites

### Required Tools

Install on macOS:
```bash
# Install required tools via Homebrew
brew install p7zip xorriso cdrtools cloud-init

# Install OpenTofu
brew install opentofu

# Install Parallels Desktop for Mac (if not already installed)
# Download from: https://www.parallels.com/
```

### Required Files
- Ubuntu 22.04.5 Server ISO for ARM64: `/Volumes/SAMSUNG/isos/ubuntu-22.04.5-live-server-arm64.iso`
- SSH key pair for VM access

## Quick Start

### 1. Build the Custom ISO

```bash
# Navigate to project directory
cd /Users/gdunn6/code/eddiedunn/kickstart

# Build the autoinstall ISO
./scripts/build-autoinstall-iso.sh /Volumes/SAMSUNG/isos/ubuntu-22.04.5-live-server-arm64.iso

# Output will be in: output/ubuntu-22.04.5-autoinstall-arm64.iso
```

### 2. Deploy with OpenTofu

```bash
# Navigate to OpenTofu directory
cd opentofu

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your settings
# - Add your SSH public key
# - Set desired hostname
# - Adjust hardware specs

# Initialize OpenTofu
tofu init

# Plan deployment
tofu plan

# Apply configuration
tofu apply
```

## Detailed Configuration

### Autoinstall Features

The `autoinstall/user-data` file configures:
- **Automatic Installation**: No user prompts required
- **Network**: DHCP configuration (Parallels default)
- **Storage**: Entire disk with direct layout
- **Users**: Temporary ubuntu user (replaced by cloud-init)
- **SSH**: Key-based authentication only
- **Packages**: Essential tools and qemu-guest-agent
- **Cloud-Init**: Enabled for first-boot configuration

### Parallels-Specific Optimizations

1. **Network Interface**: Uses `enp0s5` (Parallels ARM64 default)
2. **Guest Tools**: Installs qemu-guest-agent for VM integration
3. **Boot Configuration**: Modified GRUB for UEFI boot on ARM64
4. **Storage**: Optimized for Parallels virtual disks

### Cloud-Init Integration

Cloud-init runs on first boot to configure:
- Hostname and FQDN
- SSH authorized keys
- User accounts
- Additional packages
- System settings

## Advanced Usage

### Method 1: Embedded Cloud-Init (Recommended)

The custom ISO includes cloud-init that reads configuration from:
1. Parallels metadata service (if available)
2. NoCloud datasource on the ISO
3. Network-based datasources

### Method 2: Separate Cloud-Init ISO

For dynamic configuration without rebuilding the main ISO:

```bash
# Create cloud-init ISO for specific VM
./scripts/inject-cloud-init.sh my-vm my-hostname "ssh-rsa AAAAB3... user@host"

# Attach to VM in Parallels
prlctl set my-vm --device-add cdrom --image output/cloud-init-my-vm.iso
```

### Method 3: Direct Parallels Integration

Use Parallels tools to pass cloud-init data:

```bash
# Create VM with custom data
prlctl create my-vm --ostype ubuntu
prlctl set my-vm --custom-property "user-data=$(base64 < user-data.yaml)"
```

## OpenTofu Configuration

### Basic VM Creation

```hcl
# terraform.tfvars
vm_name        = "ubuntu-server-01"
vm_hostname    = "app-server-01"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB..."
vm_cpus        = 4
vm_memory      = 4096
vm_disk_size   = 50
```

### Multiple VMs

Create multiple VMs using for_each:

```hcl
variable "vms" {
  type = map(object({
    hostname = string
    cpus     = number
    memory   = number
  }))
  default = {
    web = { hostname = "web-01", cpus = 2, memory = 2048 }
    db  = { hostname = "db-01", cpus = 4, memory = 8192 }
  }
}

resource "parallels-desktop_vm" "servers" {
  for_each = var.vms
  name     = each.key
  # ... rest of configuration
}
```

## Troubleshooting

### ISO Build Issues

1. **Missing tools**: Install with `brew install p7zip xorriso cdrtools`
2. **Permission denied**: Ensure script is executable: `chmod +x scripts/*.sh`
3. **ISO validation**: Check with `xorriso -indev output/ubuntu-*.iso -report_el_torito as_mkisofs`

### Installation Issues

1. **Boot failure**: Verify UEFI boot is enabled in Parallels
2. **Network issues**: Check Parallels network adapter settings
3. **Cloud-init fails**: View logs with `sudo cloud-init status --long`

### Post-Installation

Access cloud-init logs:
```bash
# On the VM
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
sudo cloud-init status
```

## Security Considerations

1. **SSH Keys**: Never commit private keys to version control
2. **Passwords**: Default password is disabled after cloud-init
3. **Network**: Consider using Parallels host-only network for isolation
4. **Updates**: Enable unattended-upgrades for security patches

## Performance Tips

1. **ISO Caching**: Keep base ISO on fast storage (SSD)
2. **Parallel Builds**: Build multiple ISOs simultaneously
3. **Resource Allocation**: Don't overcommit CPU/RAM
4. **Storage**: Use Parallels expanding disks for efficiency

## Integration Examples

### CI/CD Pipeline

```yaml
# .gitlab-ci.yml example
build_vm:
  script:
    - ./scripts/build-autoinstall-iso.sh
    - cd opentofu
    - tofu init
    - tofu apply -auto-approve
```

### Ansible Integration

After VM creation, configure with Ansible:
```bash
# Get VM IP
VM_IP=$(prlctl list -f | grep ubuntu-server-01 | awk '{print $3}')

# Run Ansible
ansible-playbook -i "$VM_IP," playbook.yml
```

## Maintenance

### Updating Base ISO

When Ubuntu releases updates:
1. Download new ISO
2. Update `autoinstall/user-data` if needed
3. Rebuild custom ISO
4. Test in isolated environment
5. Update OpenTofu configurations

### Cloud-Init Updates

To update cloud-init configuration:
1. Modify user-data/meta-data files
2. Rebuild ISO or cloud-init data ISO
3. Test changes in development VM first

## Additional Resources

- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Parallels Desktop CLI Reference](https://download.parallels.com/desktop/v19/docs/en_US/Parallels%20Desktop%20Pro%20Edition%20Command-Line%20Reference.pdf)
- [OpenTofu Documentation](https://opentofu.org/docs/)