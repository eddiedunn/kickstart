# Getting Started with Ubuntu Kickstart

This guide will walk you through creating your first Ubuntu Kickstart file and deploying an automated Ubuntu installation.

## Table of Contents

1. [Understanding Ubuntu Automation](#understanding-ubuntu-automation)
2. [Prerequisites](#prerequisites)
3. [Creating Your First Kickstart File](#creating-your-first-kickstart-file)
4. [Testing Your Configuration](#testing-your-configuration)
5. [Deployment Methods](#deployment-methods)
6. [Troubleshooting](#troubleshooting)

## Understanding Ubuntu Automation

Ubuntu supports two primary automation methods:

### Preseed (Traditional)
- Debian's native automation format
- Used with debian-installer (d-i)
- More complex syntax
- Supported on all Ubuntu versions

### Kickstart (Modern)
- Red Hat's automation format
- Supported via Subiquity installer (Ubuntu 20.04+)
- Simpler, more readable syntax
- Better cloud-init integration

This guide focuses on Kickstart as it provides a cleaner syntax and better integration with modern deployment methods.

## Prerequisites

### System Requirements

```bash
# Update your system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    python3-pip \
    python3-venv \
    xorriso \
    isolinux \
    syslinux-utils \
    wget \
    curl \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virt-manager
```

### Download Ubuntu ISO

```bash
# Create working directory
mkdir -p ~/kickstart-lab
cd ~/kickstart-lab

# Download Ubuntu Server 22.04 LTS ISO
wget https://releases.ubuntu.com/22.04.4/ubuntu-22.04.4-live-server-amd64.iso
```

## Creating Your First Kickstart File

### Basic Kickstart Structure

Create a file named `my-first-kickstart.cfg`:

```yaml
#cloud-config
autoinstall:
  version: 1
  
  # Locale and keyboard settings
  locale: en_US.UTF-8
  keyboard:
    layout: us
    
  # Network configuration
  network:
    ethernets:
      eth0:
        dhcp4: true
    version: 2
    
  # Storage configuration
  storage:
    layout:
      name: lvm
      
  # User account
  identity:
    hostname: ubuntu-server
    password: "$6$exampleSalt$exampleHashedPassword"
    username: ubuntu
    
  # SSH configuration
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - "ssh-rsa AAAAB3NzaC1... your-public-key"
      
  # Package selection
  packages:
    - ubuntu-server
    - vim
    - htop
    - net-tools
    
  # Post-installation commands
  late-commands:
    - echo 'Ubuntu installation complete' > /target/etc/motd
```

### Generating a Password Hash

```bash
# Generate a secure password hash
openssl passwd -6 -salt xyz yourpassword
```

### Adding Your SSH Key

```bash
# Display your public SSH key
cat ~/.ssh/id_rsa.pub
```

## Step-by-Step: Creating a Complete Kickstart File

### Step 1: Define System Basics

```yaml
#cloud-config
autoinstall:
  version: 1
  
  # Refresh installer snap if needed
  refresh-installer:
    update: yes
    
  # Locale settings
  locale: en_US.UTF-8
  
  # Keyboard configuration
  keyboard:
    layout: us
    variant: ""
    
  # Timezone
  timezone: America/New_York
```

### Step 2: Configure Network

```yaml
  # Network configuration (using Netplan syntax)
  network:
    ethernets:
      enp0s3:  # Adjust interface name as needed
        dhcp4: true
        dhcp6: false
    version: 2
```

### Step 3: Set Up Storage

```yaml
  # Storage - LVM with separate /home
  storage:
    config:
      - type: disk
        id: disk-sda
        path: /dev/sda
        wipe: superblock-recursive
        preserve: false
        grub_device: true
        
      - type: partition
        id: partition-0
        device: disk-sda
        size: 1MB
        flag: bios_grub
        
      - type: partition
        id: partition-1
        device: disk-sda
        size: 1GB
        wipe: superblock
        flag: boot
        
      - type: format
        id: format-0
        volume: partition-1
        fstype: ext4
        
      - type: partition
        id: partition-2
        device: disk-sda
        size: -1
        wipe: superblock
        
      - type: lvm_volgroup
        id: volgroup-0
        name: ubuntu-vg
        devices:
          - partition-2
          
      - type: lvm_partition
        id: lvm-partition-0
        volgroup: volgroup-0
        name: root
        size: 20GB
        
      - type: format
        id: format-1
        volume: lvm-partition-0
        fstype: ext4
        
      - type: lvm_partition
        id: lvm-partition-1
        volgroup: volgroup-0
        name: home
        size: -1
        
      - type: format
        id: format-2
        volume: lvm-partition-1
        fstype: ext4
        
      - type: mount
        id: mount-0
        device: format-1
        path: /
        
      - type: mount
        id: mount-1
        device: format-0
        path: /boot
        
      - type: mount
        id: mount-2
        device: format-2
        path: /home
```

### Step 4: Create User Account

```yaml
  # User configuration
  identity:
    hostname: ubuntu-kickstart
    password: "$6$rounds=4096$8dkK1P/oE$2DGKKt0wLlTVJ7USY.0jN9du8FetmEr51yjPyeiR.zKE3DGFcitNL/nF1l62BLJNR87lQZixObuXYny.Mf17K1"
    realname: Ubuntu User
    username: ubuntu
```

### Step 5: Configure SSH

```yaml
  # SSH configuration
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... user@example.com
```

### Step 6: Select Packages

```yaml
  # Package selection
  packages:
    - build-essential
    - curl
    - git
    - htop
    - net-tools
    - python3-pip
    - ufw
    - unattended-upgrades
    - vim
    - wget
```

### Step 7: Post-Installation Tasks

```yaml
  # Commands to run after installation
  late-commands:
    # Update system
    - curtin in-target --target=/target -- apt-get update
    - curtin in-target --target=/target -- apt-get upgrade -y
    
    # Configure firewall
    - curtin in-target --target=/target -- ufw default deny incoming
    - curtin in-target --target=/target -- ufw default allow outgoing
    - curtin in-target --target=/target -- ufw allow ssh
    - curtin in-target --target=/target -- ufw --force enable
    
    # Set up unattended upgrades
    - curtin in-target --target=/target -- dpkg-reconfigure -plow unattended-upgrades
    
    # Create custom MOTD
    - |
      cat <<EOF > /target/etc/motd
      Welcome to Ubuntu Server
      Deployed with Kickstart Automation
      EOF
```

## Testing Your Configuration

### Method 1: Virtual Machine Testing

```bash
# Create a test VM
virt-install \
  --name ubuntu-kickstart-test \
  --ram 2048 \
  --vcpus 2 \
  --disk size=20 \
  --os-variant ubuntu22.04 \
  --network bridge=virbr0 \
  --graphics none \
  --console pty,target_type=serial \
  --location ~/kickstart-lab/ubuntu-22.04.4-live-server-amd64.iso \
  --extra-args "autoinstall ds=nocloud-net;s=http://192.168.122.1:8000/" \
  --autostart
```

### Method 2: Local HTTP Server

```bash
# Create directory for Kickstart files
mkdir -p ~/kickstart-lab/http
cp my-first-kickstart.cfg ~/kickstart-lab/http/user-data
touch ~/kickstart-lab/http/meta-data

# Start simple HTTP server
cd ~/kickstart-lab/http
python3 -m http.server 8000
```

## Deployment Methods

### ISO Integration

```bash
# Extract ISO
mkdir -p iso/mnt
sudo mount -o loop ubuntu-22.04.4-live-server-amd64.iso iso/mnt
cp -rT iso/mnt iso/extracted
sudo umount iso/mnt

# Add Kickstart file
mkdir -p iso/extracted/nocloud
cp my-first-kickstart.cfg iso/extracted/nocloud/user-data
touch iso/extracted/nocloud/meta-data

# Recreate ISO
cd iso/extracted
xorriso -as mkisofs -r \
  -V "Ubuntu Server 22.04 Kickstart" \
  -o ../../ubuntu-kickstart.iso \
  -J -l -b isolinux/isolinux.bin \
  -c isolinux/boot.cat -no-emul-boot \
  -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img \
  -no-emul-boot -isohybrid-gpt-basdat .
```

### PXE Boot Integration

```bash
# Example PXE configuration
# /tftpboot/pxelinux.cfg/default
LABEL ubuntu-kickstart
  MENU LABEL Ubuntu 22.04 Kickstart Install
  KERNEL ubuntu-22.04/vmlinuz
  INITRD ubuntu-22.04/initrd
  APPEND autoinstall ds=nocloud-net;s=http://kickstart.example.com/
```

### Cloud Deployment

```yaml
# Cloud-init user-data incorporating Kickstart
#cloud-config
autoinstall:
  version: 1
  # Your Kickstart configuration here
```

## Troubleshooting

### Common Issues

1. **Installation Hangs**
   - Check network connectivity
   - Verify Kickstart syntax
   - Review `/var/log/installer/autoinstall-user-data`

2. **Storage Configuration Fails**
   - Ensure disk paths are correct
   - Check disk size requirements
   - Verify partition alignment

3. **Network Not Working**
   - Confirm interface names
   - Check DHCP server availability
   - Verify network configuration syntax

### Debug Mode

```yaml
# Enable debug output
autoinstall:
  version: 1
  reporting:
    builtin:
      type: print
```

### Validation

```bash
# Validate cloud-config syntax
cloud-init devel schema --config-file my-first-kickstart.cfg
```

## Next Steps

1. Review [BEST_PRACTICES.md](BEST_PRACTICES.md) for production recommendations
2. Explore advanced configurations in [UBUNTU_KICKSTART_REFERENCE.md](UBUNTU_KICKSTART_REFERENCE.md)
3. Set up automation pipelines using [AUTOMATION_TOOLS.md](AUTOMATION_TOOLS.md)

## Additional Resources

- [Ubuntu Autoinstall Documentation](https://ubuntu.com/server/docs/install/autoinstall)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Netplan Reference](https://netplan.io/reference/)