# Parallels Desktop ARM64 VM Deployment Guide

## Overview
This guide provides specific recommendations for deploying Ubuntu VMs on Parallels Desktop for Apple Silicon (ARM64) Macs.

## Prerequisites

1. **Parallels Desktop Pro or Business Edition** (required for automation)
   - The standard edition has limited CLI support
   - Ensure Parallels Desktop is running before deployment

2. **OpenTofu or Terraform**
   ```bash
   brew install opentofu
   # or
   brew install terraform
   ```

3. **Ubuntu ARM64 ISO with autoinstall**
   - Must be ARM64/aarch64 version for Apple Silicon
   - Should have autoinstall configuration embedded

## ARM64-Specific Considerations

### 1. Performance Optimizations
- **Adaptive Hypervisor**: Enabled by default for better performance on Apple Silicon
- **Rosetta for Linux**: Available in Parallels 19+ for running x86_64 binaries
- **Memory**: Allocate at least 4GB for optimal performance
- **CPUs**: 2-4 vCPUs recommended (don't over-allocate)

### 2. Limitations on ARM64
- **3D Acceleration**: Not supported for Linux guests on ARM64
- **Nested Virtualization**: Limited support, disable if not needed
- **GPU Passthrough**: Not available
- **Some x86-only software**: May not run even with Rosetta

### 3. Network Configuration
- **Shared Network**: Recommended for most use cases
- **Bridged Network**: Use if VM needs to be accessible from other devices
- **Host-Only**: For isolated development environments

## Deployment Steps

### Quick Deploy (Recommended)

1. **Ensure ISO is ready**:
   ```bash
   ls -la output/ubuntu-22.04.5-autoinstall-arm64.iso
   ```

2. **Run simplified deployment**:
   ```bash
   ./scripts/deploy-vm-simple.sh
   ```

### Manual Deploy with OpenTofu

1. **Initialize OpenTofu**:
   ```bash
   cd opentofu
   tofu init
   ```

2. **Review configuration**:
   ```bash
   # Edit terraform.tfvars
   vim terraform.tfvars
   ```

3. **Plan deployment**:
   ```bash
   tofu plan
   ```

4. **Deploy VM**:
   ```bash
   tofu apply
   ```

## Troubleshooting

### ISO Validation Fails
- Ensure ISO path in terraform.tfvars is correct
- Use relative paths from the opentofu directory
- Check file permissions

### VM Creation Fails
- Verify Parallels Desktop is running
- Check you have Pro/Business edition
- Ensure sufficient disk space

### Network Issues
- Wait 5-10 minutes for installation to complete
- Check VM status: `prlctl list -a`
- Try shared network mode first

### Performance Issues
- Don't over-allocate CPUs (use 2-4)
- Ensure sufficient RAM (4GB minimum)
- Disable unused features (3D acceleration, etc.)

## Best Practices

1. **Resource Allocation**:
   - CPUs: 2-4 (don't exceed half of physical cores)
   - Memory: 4-8GB for general use
   - Disk: 30GB minimum, use expanding disks

2. **VM Configuration**:
   - Use EFI firmware (default on ARM64)
   - Enable time synchronization
   - Disable auto-compress for better performance

3. **Automation**:
   - Use terraform.tfvars for configuration
   - Keep ISOs in a consistent location
   - Version control your configurations

## VM Lifecycle Management

### Start/Stop VMs
```bash
# List VMs
prlctl list -a

# Start VM
prlctl start ubuntu-server

# Stop VM
prlctl stop ubuntu-server

# Suspend VM
prlctl suspend ubuntu-server
```

### Connect to VM
```bash
# Get IP address (after installation completes)
prlctl exec ubuntu-server ip addr show | grep "inet "

# SSH to VM
ssh ubuntu@<vm-ip>
```

### Destroy VM
```bash
cd opentofu
tofu destroy -var-file=terraform.tfvars
```

## Advanced Configuration

### Multiple VMs
Edit terraform.tfvars to use vm_definitions for deploying multiple VMs:
```hcl
vm_definitions = {
  "web" = {
    name      = "ubuntu-web"
    cpus      = 2
    memory    = 2048
    disk_size = 20
    iso_path  = "../output/ubuntu-22.04.5-autoinstall-arm64.iso"
    network   = "shared"
  }
  "db" = {
    name      = "ubuntu-db"
    cpus      = 4
    memory    = 4096
    disk_size = 50
    iso_path  = "../output/ubuntu-22.04.5-autoinstall-arm64.iso"
    network   = "shared"
  }
}
```

### Custom Network Configuration
For bridged networking:
```hcl
network_adapter {
  type = "bridged"
  mac_address = "auto"
}
```

### Headless Mode
Set in terraform.tfvars:
```hcl
headless = true  # No GUI window
```

## References
- [Parallels Desktop Documentation](https://www.parallels.com/products/desktop/resources/)
- [Parallels Provider for Terraform](https://registry.terraform.io/providers/parallels/parallels-desktop/latest)
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall)