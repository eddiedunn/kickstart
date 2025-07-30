# Ubuntu ARM64 Autoinstall Considerations

## Overview

This document outlines ARM64-specific considerations when creating Ubuntu autoinstall configurations for virtualized environments, particularly Parallels Desktop on Apple Silicon.

## Key Differences from x86_64

### 1. Boot Requirements
- ARM64 systems require UEFI boot (no legacy BIOS)
- EFI System Partition (ESP) is mandatory
- Minimum ESP size: 512MB (formatted as FAT32)
- GRUB configuration differs from x86_64

### 2. Network Interface Naming
Common interface names on ARM64 VMs:
- `enp0s5` - Parallels Desktop default
- `eth0` - Generic fallback
- `ens160` - VMware Fusion on ARM64

### 3. Virtualization Drivers
Ensure these kernel modules are loaded for optimal performance:
- `virtio_net` - Network performance
- `virtio_blk` - Block device performance
- `virtio_scsi` - SCSI device support
- `virtio_balloon` - Memory ballooning

### 4. Package Considerations
Recommended packages for ARM64 VMs:
```yaml
packages:
  - linux-tools-generic      # Performance monitoring
  - linux-cloud-tools-generic # Cloud/hypervisor integration
  - qemu-guest-agent         # QEMU/KVM guest agent
  - open-vm-tools            # VMware tools (ARM64 compatible)
```

## Storage Configuration

### Simple LVM Layout (Default)
The default `layout: lvm` with `sizing-policy: all` works well for most cases:
```yaml
storage:
  layout:
    name: lvm
    sizing-policy: all
```

### Custom Storage Layout (Advanced)
For explicit control, see `/configs/arm64-storage-example.yaml`

## Parallels Desktop Specific

### Network Configuration
Parallels typically uses `enp0s5` as the primary interface:
```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      dhcp4: true
      optional: true
```

### Guest Tools
While Parallels Tools aren't available during installation, the virtio drivers provide good performance.

## Testing Commands

### Verify Architecture
```bash
# In the VM after installation
uname -m  # Should show 'aarch64'
dpkg --print-architecture  # Should show 'arm64'
```

### Check Network Interface
```bash
ip link show
networkctl status
```

### Verify EFI Boot
```bash
efibootmgr -v
ls /sys/firmware/efi
```

## Common Issues and Solutions

### Issue: Network not available after boot
**Solution**: Add multiple interface names with `optional: true`

### Issue: Slow disk I/O
**Solution**: Ensure virtio drivers are loaded via late-commands

### Issue: Boot fails on ARM64
**Solution**: Verify EFI partition exists and is properly formatted

## Performance Optimization

1. Use virtio drivers for all devices
2. Enable memory ballooning for dynamic memory management
3. Use LVM thin provisioning for efficient storage
4. Disable unnecessary services for faster boot

## Security Considerations

1. Always disable password authentication when using SSH keys
2. Lock the default user password after key installation
3. Enable automatic security updates
4. Use firewall rules appropriate for your environment