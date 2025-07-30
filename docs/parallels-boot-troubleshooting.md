# Parallels Desktop Ubuntu 24.04 Autoinstall Boot Troubleshooting

## Overview
This guide helps troubleshoot issues when VMs boot to BIOS/UEFI instead of the Ubuntu installer when using the autoinstall ISO with Parallels Desktop and OpenTofu.

## Successfully Built ISO
The autoinstall ISO has been created at:
```
/Users/gdunn6/code/eddiedunn/kickstart/output/ubuntu-24.04.2-autoinstall-arm64-final.iso
```

This ISO includes:
- ✅ Autoinstall parameters in GRUB configuration
- ✅ Nocloud directory with user-data and meta-data
- ✅ 1-second boot timeout for automation
- ✅ EFI boot files for ARM64

## OpenTofu Configuration Requirements

### 1. Ensure Correct VM Settings
```hcl
resource "parallels-desktop_vm" "ubuntu" {
  name = "ubuntu-24-04"
  
  config {
    # CRITICAL: Must use EFI for ARM64
    firmware_type = "efi"
    
    # CRITICAL: CD-ROM must be first in boot order
    boot_order = "cdrom0,hdd0"
    
    # Hardware settings
    cpu_count   = 2
    memory_size = 2048
  }
  
  # Storage
  disk {
    size = 20480  # 20GB
  }
  
  # ISO attachment
  cdrom {
    iso_path  = "/Users/gdunn6/code/eddiedunn/kickstart/output/ubuntu-24.04.2-autoinstall-arm64-final.iso"
    connected = true
  }
  
  # Network
  network_adapter {
    mode = "shared"
  }
}
```

## Common Issues and Solutions

### Issue 1: VM Boots to BIOS/UEFI Shell
**Symptoms:** VM shows BIOS screen or UEFI shell instead of Ubuntu installer

**Solutions:**
1. **Check firmware type:** Ensure `firmware_type = "efi"` is set
2. **Check boot order:** Ensure `boot_order = "cdrom0,hdd0"`
3. **Manual boot:** In UEFI shell, type:
   ```
   fs0:
   cd efi\boot
   bootaa64.efi
   ```

### Issue 2: VM Doesn't Find Boot Device
**Symptoms:** "No bootable device" error

**Solutions:**
1. **Verify ISO path:** Ensure the ISO path in OpenTofu matches the actual file location
2. **Check CD-ROM connection:** Ensure `connected = true` in cdrom block
3. **Recreate VM:** Sometimes Parallels caches boot settings:
   ```bash
   tofu destroy -target=parallels-desktop_vm.ubuntu
   tofu apply
   ```

### Issue 3: Autoinstall Doesn't Start
**Symptoms:** Ubuntu installer starts but requires manual interaction

**Solutions:**
1. **Check console output:** Press Alt+F2 during install to see logs
2. **Verify autoinstall parameters:** Boot should show:
   ```
   linux /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/nocloud/ ---
   ```
3. **Check cloud-init logs:** After boot, check:
   ```
   /var/log/cloud-init.log
   /var/log/cloud-init-output.log
   ```

### Issue 4: Architecture Mismatch
**Symptoms:** VM fails to boot or shows compatibility errors

**Solutions:**
1. **Verify host architecture:**
   ```bash
   uname -m  # Should show arm64 on Apple Silicon
   ```
2. **Ensure ARM64 ISO:** The ISO filename should contain "arm64"
3. **Check Parallels VM type:** Must be ARM64 VM on Apple Silicon

## Verification Steps

### 1. Verify ISO Contents
```bash
# Check for autoinstall parameters
xorriso -osirrox on -indev /path/to/iso \
  -extract /boot/grub/grub.cfg - | grep autoinstall

# Check for nocloud directory
xorriso -indev /path/to/iso -find /nocloud -exec lsdl --
```

### 2. Test Boot Manually in Parallels
1. Create a new VM manually in Parallels Desktop
2. Settings:
   - Type: Ubuntu
   - Version: Ubuntu 24.04
   - Boot options: EFI enabled
   - CD/DVD: Point to the autoinstall ISO
3. Start VM and observe boot process

### 3. Monitor Installation Progress
During installation:
- Press Alt+F2 for console access
- Check `/var/log/installer/autoinstall-user-data`
- Monitor `/var/log/syslog` for errors

## Working Example Output
When working correctly, you should see:
1. GRUB menu appears for 1 second
2. "Try or Install Ubuntu Server" is automatically selected
3. Boot messages show autoinstall parameters
4. Installation proceeds without prompts
5. VM reboots after completion

## Additional Resources
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall)
- [Parallels Desktop Documentation](https://www.parallels.com/products/desktop/documentation/)
- [OpenTofu Parallels Provider](https://registry.terraform.io/providers/parallels/parallels-desktop/latest/docs)