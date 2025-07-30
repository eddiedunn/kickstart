# Troubleshooting Guide

This comprehensive guide helps resolve common issues when deploying Ubuntu VMs with autoinstall, templates, and cloud-init on Parallels Desktop.

## Table of Contents

1. [ISO Build and Boot Issues](#iso-build-and-boot-issues)
2. [VM Creation and Deployment Issues](#vm-creation-and-deployment-issues)
3. [Template-Related Issues](#template-related-issues)
4. [Cloud-Init Problems](#cloud-init-problems)
5. [Network Configuration Issues](#network-configuration-issues)
6. [Storage and Disk Issues](#storage-and-disk-issues)
7. [OpenTofu/Terraform Issues](#opentofuterraform-issues)
8. [Performance Problems](#performance-problems)
9. [Security and Access Issues](#security-and-access-issues)
10. [Diagnostic Commands](#diagnostic-commands)

## ISO Build and Boot Issues

### Issue: ISO Build Script Fails

**Symptoms:**
- Script exits with error
- Missing files in output
- Permission denied errors

**Solutions:**

1. **Check Prerequisites**
   ```bash
   # Ensure required tools are installed
   which xorriso || brew install xorriso
   which 7z || brew install p7zip
   
   # Check perl is available (for isohdpfx.bin extraction)
   perl --version
   ```

2. **Verify Input ISO**
   ```bash
   # Check ISO exists and is readable
   ls -la /path/to/ubuntu.iso
   file /path/to/ubuntu.iso
   
   # Verify it's a valid Ubuntu Server ISO
   xorriso -indev /path/to/ubuntu.iso -find / -exec lsdl
   ```

3. **Check Permissions**
   ```bash
   # Ensure script is executable
   chmod +x scripts/build-autoinstall-iso.sh
   
   # Check output directory permissions
   mkdir -p output
   chmod 755 output
   ```

### Issue: VM Boots to BIOS/UEFI Instead of Installer

**Symptoms:**
- VM shows BIOS/UEFI shell
- "No bootable device" error
- Installer doesn't start automatically

**Solutions:**

1. **Verify OpenTofu Configuration**
   ```hcl
   # Ensure correct firmware type for architecture
   resource "parallels-desktop_vm" "ubuntu" {
     config {
       firmware_type = "efi"  # Required for ARM64
       boot_order   = "cdrom0,hdd0"  # CD-ROM must be first
     }
   }
   ```

2. **Check ISO is Attached**
   ```bash
   # Verify CD-ROM device
   prlctl list -i <vm-name> | grep -i cdrom
   
   # Should show:
   # cdrom0 (+) real='path/to/iso' state=connected
   ```

3. **Manual UEFI Boot (ARM64)**
   ```bash
   # If dropped to UEFI shell
   fs0:
   cd efi\boot
   bootaa64.efi
   ```

4. **Recreate VM**
   ```bash
   # Sometimes Parallels caches boot settings
   tofu destroy -target=parallels-desktop_vm.ubuntu
   tofu apply
   ```

### Issue: Autoinstall Doesn't Start Automatically

**Symptoms:**
- Ubuntu installer starts but requires manual interaction
- Stops at language selection or network configuration

**Solutions:**

1. **Verify Autoinstall Parameters**
   ```bash
   # Check GRUB configuration in ISO
   xorriso -osirrox on -indev output/ubuntu-autoinstall.iso \
     -extract /boot/grub/grub.cfg - | grep autoinstall
   
   # Should contain:
   # linux /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/nocloud/ ---
   ```

2. **Check Cloud-Init Data**
   ```bash
   # Verify nocloud directory exists in ISO
   xorriso -indev output/ubuntu-autoinstall.iso -find /nocloud -exec lsdl
   
   # Extract and validate user-data
   xorriso -osirrox on -indev output/ubuntu-autoinstall.iso \
     -extract /nocloud/user-data - | cloud-init devel schema --config-file -
   ```

3. **Enable Debug Mode**
   ```yaml
   # Add to autoinstall configuration
   autoinstall:
     version: 1
     interactive-sections:
       - network  # Make network section interactive for debugging
   ```

## VM Creation and Deployment Issues

### Issue: OpenTofu Fails to Create VM

**Symptoms:**
- "Provider produced inconsistent result" error
- VM creation timeout
- Resource already exists errors

**Solutions:**

1. **Check Parallels Desktop Status**
   ```bash
   # Ensure Parallels Desktop is running
   prlctl list -a
   
   # Check Parallels service
   prlsrvctl info
   
   # Restart if needed
   sudo launchctl stop com.parallels.desktop.launchdaemon
   sudo launchctl start com.parallels.desktop.launchdaemon
   ```

2. **Clean State and Retry**
   ```bash
   # Remove state file
   rm terraform.tfstate*
   
   # Check for orphaned VMs
   prlctl list -a | grep ubuntu
   
   # Remove orphaned VMs
   prlctl delete <vm-uuid> --force
   
   # Reinitialize and apply
   tofu init -upgrade
   tofu apply
   ```

3. **Increase Timeouts**
   ```hcl
   resource "parallels-desktop_vm" "ubuntu" {
     timeout {
       create = "45m"  # Increase from default 30m
       stop   = "10m"
     }
   }
   ```

### Issue: VM Gets No IP Address

**Symptoms:**
- `prlctl list -f` shows no IP
- Can't SSH to VM
- Network adapter not working

**Solutions:**

1. **Wait for Installation Completion**
   ```bash
   # Installation can take 5-20 minutes
   # Monitor with:
   ./scripts/status.sh --watch
   ```

2. **Check Network Mode**
   ```bash
   # Verify network adapter settings
   prlctl list -i <vm-name> | grep -i network
   
   # Should show:
   # net0 (+) type=shared mac=<MAC>
   ```

3. **Check DHCP in Parallels**
   ```bash
   # List Parallels networks
   prlsrvctl net list
   
   # Check DHCP settings
   prlsrvctl net info "Shared"
   ```

4. **Access VM Console**
   ```bash
   # Open console to check network manually
   prlctl enter <vm-name>
   
   # Inside VM:
   ip addr show
   sudo dhclient -v enp0s5
   ```

## Template-Related Issues

### Issue: Template Creation Fails

**Symptoms:**
- "VM is not stopped" error
- "Cannot create template" error
- Script hangs during preparation

**Solutions:**

1. **Ensure VM is Stopped**
   ```bash
   # Stop VM gracefully
   prlctl stop <vm-name> --kill
   
   # Wait for complete stop
   while prlctl status <vm-name> | grep -q running; do
     sleep 1
   done
   ```

2. **Check Disk Space**
   ```bash
   # Templates require significant space
   df -h ~/Parallels
   
   # Clean up if needed
   prlctl list -a --template
   prlctl delete <old-template> --force
   ```

3. **Manual Template Creation**
   ```bash
   # If script fails, try manually
   prlctl stop <vm-name>
   prlctl clone <vm-name> --name <template-name> --template
   ```

### Issue: Template Clone Fails

**Symptoms:**
- "Source template not found"
- "Linked clone base missing"
- Disk space errors

**Solutions:**

1. **Verify Template Exists**
   ```bash
   # List all templates
   prlctl list -t
   
   # Check template details
   prlctl list -i <template-name>
   ```

2. **Fix Linked Clone Issues**
   ```bash
   # For linked clones, ensure base template hasn't moved
   # If moved, recreate template or use full clone:
   prlctl clone <template> --name <new-vm>  # Without --linked
   ```

3. **Check Permissions**
   ```bash
   # Ensure read access to template files
   ls -la ~/Parallels/<template-name>.pvm/
   ```

### Issue: Cloud-Init Doesn't Run in Cloned VMs

**Symptoms:**
- Hostname not changed
- SSH keys not injected
- Packages not installed

**Solutions:**

1. **Verify Cloud-Init in Template**
   ```bash
   # Check if cloud-init was cleaned properly
   prlctl exec <template-name> "ls -la /var/lib/cloud/"
   
   # Should be empty or not exist
   ```

2. **Check Cloud-Init ISO Creation**
   ```bash
   # Verify cloud-init ISO is attached
   prlctl list -i <vm-name> | grep cdrom
   
   # Should show cloud-init ISO attached
   ```

3. **Debug Cloud-Init**
   ```bash
   # Access VM console
   prlctl enter <vm-name>
   
   # Check cloud-init status
   cloud-init status --long
   
   # View logs
   sudo journalctl -u cloud-init
   sudo cat /var/log/cloud-init.log
   ```

## Cloud-Init Problems

### Issue: Cloud-Init Fails with "No datasource found"

**Symptoms:**
- Cloud-init doesn't find configuration
- Default configuration applied
- No customization happens

**Solutions:**

1. **Check Datasource Configuration**
   ```yaml
   # Ensure datasource_list includes NoCloud
   datasource_list: [ NoCloud, None ]
   ```

2. **Verify Cloud-Init ISO**
   ```bash
   # Mount and check cloud-init ISO
   mkdir -p /tmp/ci-check
   sudo mount -o loop,ro cloud-init-<vm>.iso /tmp/ci-check
   ls -la /tmp/ci-check/
   
   # Should contain:
   # - user-data
   # - meta-data
   
   sudo umount /tmp/ci-check
   ```

3. **Check File Headers**
   ```bash
   # user-data must start with #cloud-config
   head -1 user-data
   # Should show: #cloud-config
   ```

### Issue: Cloud-Init Runs But Doesn't Apply Configuration

**Symptoms:**
- Cloud-init completes successfully
- Configuration not applied
- No error messages

**Solutions:**

1. **Validate Configuration Syntax**
   ```bash
   # Check YAML syntax
   cloud-init devel schema --config-file user-data
   
   # Check for indentation errors
   python3 -c "import yaml; yaml.safe_load(open('user-data'))"
   ```

2. **Check Module Execution**
   ```bash
   # View which modules ran
   cloud-init analyze show
   
   # Check specific module logs
   grep -A5 -B5 "module_name" /var/log/cloud-init.log
   ```

3. **Common Configuration Issues**
   ```yaml
   # Wrong - missing #cloud-config header
   hostname: my-server
   
   # Correct
   #cloud-config
   hostname: my-server
   
   # Wrong - incorrect indentation
   users:
   - name: ubuntu
   
   # Correct
   users:
     - name: ubuntu
   ```

## Network Configuration Issues

### Issue: Static IP Not Applied

**Symptoms:**
- VM still using DHCP
- Wrong IP address assigned
- Network unreachable

**Solutions:**

1. **Check Network Configuration Format**
   ```yaml
   # Correct format for autoinstall
   network:
     version: 2
     ethernets:
       enp0s5:  # Verify interface name!
         addresses:
           - 192.168.1.100/24
         routes:
           - to: default
             via: 192.168.1.1
         nameservers:
           addresses:
             - 8.8.8.8
             - 8.8.4.4
   ```

2. **Verify Interface Name**
   ```bash
   # Get correct interface name
   prlctl exec <vm-name> "ip link show"
   
   # Common names:
   # - enp0s5 (ARM64)
   # - enp0s3 (x86_64)
   # - eth0 (older systems)
   ```

3. **Apply Network Configuration**
   ```bash
   # If using netplan
   sudo netplan generate
   sudo netplan apply
   
   # Check configuration
   sudo netplan --debug apply
   ```

### Issue: DNS Resolution Failing

**Symptoms:**
- Can ping IPs but not hostnames
- apt update fails
- "Temporary failure resolving" errors

**Solutions:**

1. **Check DNS Configuration**
   ```bash
   # View current DNS settings
   resolvectl status
   systemd-resolve --status
   
   # Check /etc/resolv.conf
   ls -la /etc/resolv.conf
   cat /etc/resolv.conf
   ```

2. **Fix systemd-resolved**
   ```bash
   # Restart systemd-resolved
   sudo systemctl restart systemd-resolved
   
   # If using static DNS
   sudo mkdir -p /etc/systemd/resolved.conf.d/
   echo "[Resolve]
   DNS=8.8.8.8 8.8.4.4
   FallbackDNS=1.1.1.1" | sudo tee /etc/systemd/resolved.conf.d/dns.conf
   ```

## Storage and Disk Issues

### Issue: Installation Fails with Storage Errors

**Symptoms:**
- "No disk found" errors
- Partition table errors
- Installation stops at storage configuration

**Solutions:**

1. **Check Disk Configuration**
   ```yaml
   # Ensure disk path exists
   storage:
     config:
       - type: disk
         id: disk-sda
         path: /dev/sda  # Verify this exists!
         wipe: superblock-recursive
   ```

2. **Verify Disk in VM**
   ```bash
   # During installation (Alt+F2 for console)
   lsblk
   ls -la /dev/sd* /dev/nvme*
   
   # Check disk size
   fdisk -l
   ```

3. **Use Guided Layout**
   ```yaml
   # Simpler configuration
   storage:
     layout:
       name: lvm
       sizing-policy: all
   ```

### Issue: Disk Space Runs Out During Installation

**Symptoms:**
- Installation fails partway through
- "No space left on device" errors
- VM disk appears smaller than configured

**Solutions:**

1. **Increase VM Disk Size**
   ```hcl
   # In terraform.tfvars
   vm_disk_size = 51200  # 50GB in MB
   ```

2. **Check Parallels Disk Settings**
   ```bash
   # Verify disk size
   prlctl list -i <vm-name> | grep hdd0
   
   # Resize if needed
   prlctl set <vm-name> --device-set hdd0 --size 50G
   ```

## OpenTofu/Terraform Issues

### Issue: Provider Plugin Errors

**Symptoms:**
- "Failed to query available provider packages"
- "Provider produced inconsistent result"
- Version constraint errors

**Solutions:**

1. **Update Provider**
   ```hcl
   terraform {
     required_providers {
       parallels-desktop = {
         source  = "parallels/parallels-desktop"
         version = "~> 0.3.0"  # Use latest version
       }
     }
   }
   ```

2. **Clean and Reinitialize**
   ```bash
   # Remove provider plugins
   rm -rf .terraform
   rm .terraform.lock.hcl
   
   # Reinitialize
   tofu init -upgrade
   ```

3. **Check Provider Configuration**
   ```bash
   # Verify provider is installed
   tofu providers
   
   # Show provider requirements
   tofu version
   ```

### Issue: State Lock Errors

**Symptoms:**
- "Error acquiring the state lock"
- "Resource already being modified"
- Can't run apply or destroy

**Solutions:**

1. **Force Unlock**
   ```bash
   # Get lock ID from error message
   tofu force-unlock <lock-id>
   ```

2. **Check for Running Operations**
   ```bash
   # Ensure no other Terraform processes
   ps aux | grep terraform
   ps aux | grep tofu
   ```

3. **Remove Lock File**
   ```bash
   # If using local state
   rm .terraform.lock.hcl
   rm terraform.tfstate.lock.info
   ```

## Performance Problems

### Issue: VM Installation Very Slow

**Symptoms:**
- Installation takes over 30 minutes
- Progress bar barely moves
- High CPU/disk usage

**Solutions:**

1. **Check Host Resources**
   ```bash
   # Monitor host performance
   top
   iostat -x 1
   
   # Check Parallels resource usage
   ps aux | grep prl
   ```

2. **Optimize VM Resources**
   ```hcl
   # Increase resources for installation
   resource "parallels-desktop_vm" "ubuntu" {
     config {
       cpu_count   = 4  # More CPUs for faster install
       memory_size = 4096
       
       # Performance settings
       adaptive_hypervisor = true
       hypervisor_type    = "parallels"
     }
   }
   ```

3. **Use Local Mirror**
   ```yaml
   # Configure local APT mirror
   apt:
     primary:
       - arches: [arm64]
         uri: "http://local-mirror/ubuntu"
   ```

### Issue: Template Cloning Slow

**Symptoms:**
- Linked clones taking minutes
- High disk I/O during clone
- System becomes unresponsive

**Solutions:**

1. **Check Disk Type**
   ```bash
   # Ensure using SSD for VMs
   diskutil info disk0 | grep "Solid State"
   
   # Check available space
   df -h ~/Parallels
   ```

2. **Optimize Clone Type**
   ```bash
   # Use linked clones for speed
   prlctl clone <template> --name <new-vm> --linked
   
   # Avoid full clones unless necessary
   ```

## Security and Access Issues

### Issue: Can't SSH to VM

**Symptoms:**
- "Permission denied" errors
- "Connection refused"
- Timeout connecting

**Solutions:**

1. **Verify SSH Service**
   ```bash
   # Check if SSH is running
   prlctl exec <vm-name> "systemctl status ssh"
   
   # Start if needed
   prlctl exec <vm-name> "sudo systemctl start ssh"
   ```

2. **Check SSH Configuration**
   ```bash
   # Verify password auth is disabled
   prlctl exec <vm-name> "grep PasswordAuthentication /etc/ssh/sshd_config"
   
   # Check authorized_keys
   prlctl exec <vm-name> "ls -la ~/.ssh/authorized_keys"
   ```

3. **Verify Firewall**
   ```bash
   # Check UFW status
   prlctl exec <vm-name> "sudo ufw status"
   
   # Ensure SSH is allowed
   prlctl exec <vm-name> "sudo ufw allow ssh"
   ```

### Issue: Default Password Not Working

**Symptoms:**
- Can't login with configured password
- "Authentication failure" at console
- Password appears to be wrong

**Solutions:**

1. **Check Password Hash**
   ```bash
   # Generate new hash
   openssl passwd -6 -salt xyz yourpassword
   
   # Ensure using hashed password in config
   ```

2. **Reset Password via Console**
   ```bash
   # Access VM console
   prlctl enter <vm-name>
   
   # Login as root (if possible) or use recovery mode
   # Reset password
   passwd ubuntu
   ```

3. **Use Cloud-Init to Reset**
   ```yaml
   #cloud-config
   chpasswd:
     users:
       - name: ubuntu
         password: newpassword
         type: text
   ```

## Diagnostic Commands

### General VM Information
```bash
# List all VMs with details
prlctl list -a -f

# Get specific VM info
prlctl list -i <vm-name>

# Check VM status
prlctl status <vm-name>

# View VM configuration
prlctl list -i <vm-name> --json
```

### Network Diagnostics
```bash
# Check Parallels networks
prlsrvctl net list

# Get network details
prlsrvctl net info "Shared"

# Check VM network from host
ping $(prlctl list -f | grep <vm-name> | awk '{print $3}')

# Check connectivity from VM
prlctl exec <vm-name> "ping -c 3 8.8.8.8"
prlctl exec <vm-name> "curl -I https://ubuntu.com"
```

### Storage Diagnostics
```bash
# Check VM disk usage
prlctl exec <vm-name> "df -h"

# View disk configuration
prlctl list -i <vm-name> | grep hdd

# Check host disk space
df -h ~/Parallels
```

### Cloud-Init Diagnostics
```bash
# Check cloud-init status
prlctl exec <vm-name> "cloud-init status --long"

# Analyze cloud-init performance
prlctl exec <vm-name> "cloud-init analyze show"

# Collect all cloud-init logs
prlctl exec <vm-name> "cloud-init collect-logs"

# View specific stage logs
prlctl exec <vm-name> "cat /var/log/cloud-init-output.log"
```

### Installation Logs
```bash
# View installer logs (during or after install)
prlctl exec <vm-name> "cat /var/log/installer/autoinstall-user-data"
prlctl exec <vm-name> "cat /var/log/installer/subiquity-server-debug.log"
prlctl exec <vm-name> "cat /var/log/installer/curtin-install.log"

# Check for errors
prlctl exec <vm-name> "grep -i error /var/log/installer/*.log"
```

### Performance Monitoring
```bash
# Monitor VM resource usage
prlctl statistics <vm-name>

# Check VM performance
prlctl exec <vm-name> "top -b -n 1"
prlctl exec <vm-name> "iostat -x 1 5"
prlctl exec <vm-name> "free -h"
```

## Getting Additional Help

If issues persist:

1. **Check Logs**
   - Parallels: `/var/log/parallels.log`
   - VM logs: `/var/log/` inside VM
   - OpenTofu: `TF_LOG=DEBUG tofu apply`

2. **Enable Debug Mode**
   - Autoinstall: Add `reporting: {builtin: {type: print, level: DEBUG}}`
   - Cloud-init: Add `debug: true` to configuration
   - OpenTofu: Set `TF_LOG=DEBUG`

3. **Community Resources**
   - Ubuntu Forums: https://discourse.ubuntu.com/
   - Parallels Forums: https://forum.parallels.com/
   - Project Issues: Check GitHub issues

4. **File Bug Reports**
   - Include all relevant logs
   - Provide minimal reproduction steps
   - List versions of all tools used