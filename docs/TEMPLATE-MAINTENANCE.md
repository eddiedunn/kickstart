# Template Maintenance Guide

This guide documents how to create and update Ubuntu VM templates for use with this project.

## Overview

Templates are pre-configured VMs that can be cloned in seconds. This guide covers:
- Creating a new template from scratch
- Updating existing templates with patches
- Best practices for template versioning

## Creating a New Template

### Step 1: Deploy Base VM

```bash
# Use the minimal ISO for fastest installation
./scripts/deploy-vm.sh output/ubuntu-minimal-autoinstall-*.iso ubuntu-template-base
```

Wait for installation to complete (5-10 minutes). The VM will have:
- Username: `ubuntu`
- Password: `ubuntu`
- Basic Ubuntu Server installation

### Step 2: Configure the VM

SSH into the VM:
```bash
ssh ubuntu@<VM_IP>  # Password: ubuntu
```

Run these commands to update and configure:
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Configure passwordless sudo
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ubuntu

# Install useful packages
sudo apt install -y curl wget git btop htop net-tools build-essential

# Prepare for Parallels Tools
sudo apt install -y linux-headers-$(uname -r) dkms

# Clean up
sudo apt clean && sudo apt autoremove -y
```

### Step 3: Install Parallels Tools

1.
```bash
sudo eject /dev/sr0
```
2. In Parallels Desktop menu: **Actions > Install Parallels Tools**
3. In the VM terminal:
   ```bash
   sudo mount /dev/cdrom /mnt
   sudo /mnt/install
   ```
4. Reboot when prompted

### Step 4: Prepare for Template

After reboot, run from your host machine:
```bash
./scripts/prepare-vm-template.sh ubuntu-template-base
```

This script:
- Removes SSH host keys
- Clears logs and caches
- Prepares cloud-init for first boot

### Step 5: Create Template

```bash
./scripts/create-parallels-template.sh ubuntu-template-base all
```

This creates:
- `ubuntu-template-base-template` - Linked clone template
- `ubuntu-template-base-YYYYMMDD.pvm` - Portable bundle
- Snapshot for rollback

## Updating Existing Templates

### Monthly Update Process

1. **Clone the template to a working VM**
   ```bash
   prlctl clone ubuntu-template-base-template --name update-work-vm
   ```

2. **Start and update the VM**
   ```bash
   prlctl start update-work-vm
   # Wait for IP, then SSH in
   ssh ubuntu@<VM_IP>
   
   # Run updates
   sudo apt update && sudo apt upgrade -y
   sudo apt autoremove -y
   ```

3. **Create new versioned template**
   ```bash
   # Prepare the updated VM
   ./scripts/prepare-vm-template.sh update-work-vm
   
   # Create new template with version
   ./scripts/create-parallels-template.sh update-work-vm all
   
   # Rename to versioned name
   prlctl set update-work-vm-template --name ubuntu-22.04-template-$(date +%Y%m)
   ```

4. **Clean up**
   ```bash
   prlctl delete update-work-vm
   ```

## Template Naming Convention

Use semantic versioning for templates:
- `ubuntu-22.04-template-202401` - January 2024 update
- `ubuntu-22.04-template-202402` - February 2024 update
- `ubuntu-22.04-template-latest` - Symlink to current version

## Best Practices

1. **Document Changes**: Keep a CHANGELOG for each template version
2. **Test Before Release**: Always test cloning before marking as latest
3. **Keep Previous Version**: Don't delete old template until new one is proven
4. **Regular Updates**: Update templates monthly for security patches
5. **Minimal Base**: Keep templates minimal - use cloud-init for customization

## Troubleshooting

### Parallels Tools Won't Install
- Ensure VM has kernel headers: `sudo apt install linux-headers-$(uname -r)`
- Check CD is mounted: `ls /dev/cdrom`
- Review install log: `/var/log/parallels-tools-install.log`

### Template Won't Clone
- Check disk space: `df -h`
- Verify template status: `prlctl list -t`
- Ensure template is stopped: `prlctl stop <template-name>`

### SSH Access Issues
- Default credentials: ubuntu/ubuntu
- Check IP: `prlctl list -f | grep <vm-name>`
- Verify SSH service: `prlctl exec <vm-name> "systemctl status ssh"`

## Next Steps

After creating/updating templates:
1. Update `terraform.tfvars` with new template name
2. Test deployment with `tofu apply`
3. Update team documentation with new version