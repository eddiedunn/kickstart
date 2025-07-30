# Technical Reference

This document provides comprehensive technical details for Ubuntu Kickstart automation, cloud-init integration, and Parallels Desktop VM configuration.

## Table of Contents

1. [Ubuntu Autoinstall Architecture](#ubuntu-autoinstall-architecture)
2. [Configuration File Formats](#configuration-file-formats)
3. [Network Configuration Details](#network-configuration-details)
4. [Storage Configuration Details](#storage-configuration-details)
5. [Cloud-Init Integration](#cloud-init-integration)
6. [Parallels Desktop Specifics](#parallels-desktop-specifics)
7. [OpenTofu/Terraform Configuration](#opentofuterraform-configuration)
8. [Security Implementation](#security-implementation)
9. [Performance Optimization](#performance-optimization)
10. [Advanced Configurations](#advanced-configurations)

## Ubuntu Autoinstall Architecture

### Overview

Ubuntu's autoinstall system uses the Subiquity installer with cloud-init style configuration files. This modern approach replaces the traditional debian-installer (d-i) preseed system.

### Key Components

1. **Subiquity Server**: The backend installation engine
2. **Cloud-Init**: Configuration and customization framework
3. **Curtin**: The actual installation tool
4. **Netplan**: Network configuration system

### Installation Flow

```
Boot → GRUB → Kernel → Initramfs → Subiquity → Cloud-Init → Curtin → Reboot → Cloud-Init (first boot)
```

### File Structure Requirements

```yaml
#cloud-config
autoinstall:
  version: 1  # Required, currently only version 1 supported
  # All autoinstall directives go here
```

## Configuration File Formats

### Autoinstall YAML Structure

```yaml
#cloud-config
autoinstall:
  version: 1
  
  # Installer behavior
  refresh-installer:
    update: yes
    channel: stable
  
  # Interactive sections (empty = fully automated)
  interactive-sections: []
  
  # Reporting configuration
  reporting:
    builtin:
      type: print
      level: INFO
  
  # Early commands (before installation)
  early-commands:
    - echo "Starting installation at $(date)" > /tmp/install.log
  
  # Error handling
  error-commands:
    - tar czf /tmp/install-logs.tar.gz /var/log/
  
  # All other configuration sections...
```

### Required vs Optional Sections

**Required:**
- `version`: Must be 1
- `identity`: User account information
- `storage` or `storage.layout`: Disk configuration

**Optional but Recommended:**
- `ssh`: SSH server configuration
- `network`: Network configuration
- `packages`: Additional packages
- `late-commands`: Post-installation commands

### Validation

```bash
# Validate syntax
cloud-init devel schema --config-file user-data

# Check specific module
cloud-init devel schema -m cc_autoinstall --annotate
```

## Network Configuration Details

### Network Version 2 Format (Netplan)

The autoinstall system uses Netplan's version 2 format for network configuration.

### Basic DHCP Configuration

```yaml
network:
  version: 2
  renderer: networkd  # or NetworkManager
  ethernets:
    enp0s5:  # Interface name (Parallels default for ARM64)
      dhcp4: true
      dhcp6: false
      dhcp4-overrides:
        use-dns: true
        use-ntp: true
        use-hostname: false
        use-routes: true
```

### Static IP Configuration

```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default  # or 0.0.0.0/0
          via: 192.168.1.1
          metric: 100
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
        search:
          - example.com
          - internal.example.com
      optional: false  # Wait for interface to come up
```

### Advanced Network Configurations

#### Bond Configuration
```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      dhcp4: false
    enp0s6:
      dhcp4: false
  bonds:
    bond0:
      interfaces:
        - enp0s5
        - enp0s6
      parameters:
        mode: active-backup  # or 802.3ad, balance-rr, etc.
        primary: enp0s5
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
      addresses:
        - 192.168.1.100/24
```

#### VLAN Configuration
```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      dhcp4: false
  vlans:
    vlan10:
      id: 10
      link: enp0s5
      addresses:
        - 10.10.10.100/24
      routes:
        - to: default
          via: 10.10.10.1
```

#### Bridge Configuration
```yaml
network:
  version: 2
  ethernets:
    enp0s5:
      dhcp4: false
  bridges:
    br0:
      interfaces:
        - enp0s5
      addresses:
        - 192.168.1.100/24
      parameters:
        stp: true
        forward-delay: 4
        hello-time: 2
        max-age: 20
        priority: 32768
```

### Network Interface Detection

For dynamic interface matching:
```yaml
network:
  version: 2
  ethernets:
    primary-nic:
      match:
        name: en*  # Match any ethernet interface
      dhcp4: true
```

## Storage Configuration Details

### Storage Layout Options

#### Guided Layouts

Simple layout specifications:
```yaml
storage:
  layout:
    name: lvm  # or direct, zfs
    sizing-policy: scaled  # or all
    encryption:
      passphrase: "encryption-password"
```

#### Custom Partitioning

Full control over disk layout:
```yaml
storage:
  config:
    # Define disk
    - type: disk
      id: disk-sda
      path: /dev/sda
      wipe: superblock-recursive
      preserve: false
      grub_device: true
      
    # EFI partition (UEFI systems)
    - type: partition
      id: partition-efi
      device: disk-sda
      size: 512MB
      flag: boot
      grub_device: true
      
    - type: format
      id: format-efi
      volume: partition-efi
      fstype: fat32
      label: EFI
      
    # Boot partition
    - type: partition
      id: partition-boot
      device: disk-sda
      size: 1GB
      
    - type: format
      id: format-boot
      volume: partition-boot
      fstype: ext4
      label: BOOT
      
    # Root partition (remaining space)
    - type: partition
      id: partition-root
      device: disk-sda
      size: -1  # Use remaining space
      
    - type: format
      id: format-root
      volume: partition-root
      fstype: ext4
      label: ROOT
      
    # Mount points
    - type: mount
      id: mount-root
      device: format-root
      path: /
      
    - type: mount
      id: mount-boot
      device: format-boot
      path: /boot
      
    - type: mount
      id: mount-efi
      device: format-efi
      path: /boot/efi
```

### LVM Configuration

```yaml
storage:
  config:
    # Physical disk
    - type: disk
      id: disk-sda
      path: /dev/sda
      wipe: superblock
      preserve: false
      grub_device: true
      
    # Boot partition (outside LVM)
    - type: partition
      id: partition-boot
      device: disk-sda
      size: 1GB
      flag: boot
      
    - type: format
      id: format-boot
      volume: partition-boot
      fstype: ext4
      
    # LVM partition
    - type: partition
      id: partition-lvm
      device: disk-sda
      size: -1
      
    # Volume group
    - type: lvm_volgroup
      id: vg-ubuntu
      name: ubuntu-vg
      devices:
        - partition-lvm
        
    # Logical volumes
    - type: lvm_partition
      id: lv-root
      name: root
      volgroup: vg-ubuntu
      size: 20GB
      
    - type: lvm_partition
      id: lv-home
      name: home
      volgroup: vg-ubuntu
      size: 50GB
      
    - type: lvm_partition
      id: lv-var
      name: var
      volgroup: vg-ubuntu
      size: 30GB
      
    - type: lvm_partition
      id: lv-swap
      name: swap
      volgroup: vg-ubuntu
      size: 4GB
      
    # Formats
    - type: format
      id: format-root
      volume: lv-root
      fstype: ext4
      
    - type: format
      id: format-home
      volume: lv-home
      fstype: ext4
      
    - type: format
      id: format-var
      volume: lv-var
      fstype: ext4
      
    - type: format
      id: format-swap
      volume: lv-swap
      fstype: swap
      
    # Mounts
    - type: mount
      id: mount-root
      device: format-root
      path: /
      
    - type: mount
      id: mount-boot
      device: format-boot
      path: /boot
      
    - type: mount
      id: mount-home
      device: format-home
      path: /home
      
    - type: mount
      id: mount-var
      device: format-var
      path: /var
```

### RAID Configuration

```yaml
storage:
  config:
    # Multiple disks
    - type: disk
      id: disk-sda
      path: /dev/sda
      wipe: superblock
      
    - type: disk
      id: disk-sdb
      path: /dev/sdb
      wipe: superblock
      
    # Partitions for RAID
    - type: partition
      id: part-sda1
      device: disk-sda
      size: -1
      
    - type: partition
      id: part-sdb1
      device: disk-sdb
      size: -1
      
    # RAID array
    - type: raid
      id: raid-1
      name: md0
      raidlevel: raid1  # or raid0, raid5, raid6, raid10
      devices:
        - part-sda1
        - part-sdb1
      spare_devices: []
      
    # Format and mount RAID
    - type: format
      id: format-raid
      volume: raid-1
      fstype: ext4
      
    - type: mount
      id: mount-raid
      device: format-raid
      path: /
```

## Cloud-Init Integration

### Merge Behavior

Cloud-init configuration can be included in the autoinstall file and will be processed at different stages:

```yaml
#cloud-config
# These run during installation
autoinstall:
  version: 1
  late-commands:
    - echo "During installation" > /target/tmp/install.log

# These run on first boot after installation
users:
  - name: clouduser
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL

runcmd:
  - echo "First boot" > /tmp/firstboot.log
```

### Datasources

#### NoCloud (Local Files)
Used when configuration is provided via ISO or local files:
```yaml
datasource:
  NoCloud:
    fs_label: cidata
    user-data: |
      #cloud-config
      hostname: configured-by-nocloud
    meta-data: |
      instance-id: iid-local01
```

#### Network Datasources
For fetching configuration from network:
```yaml
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    seedfrom: http://192.168.1.100:8000/
```

### Cloud-Init Modules Execution Order

1. **Init Stage** (cloud-init init)
   - Network configuration
   - Filesystem setup
   - Initial user creation

2. **Config Stage** (cloud-init modules --mode=config)
   - Package installation
   - File writing
   - Additional user configuration

3. **Final Stage** (cloud-init modules --mode=final)
   - User scripts (runcmd)
   - Final message
   - Power state changes

### Debugging Cloud-Init

```bash
# Check cloud-init status
cloud-init status --long

# Analyze boot stages
cloud-init analyze show

# View collected logs
cloud-init collect-logs

# Re-run cloud-init
cloud-init clean --logs
cloud-init init
```

## Parallels Desktop Specifics

### ARM64 Architecture Considerations

1. **Network Interface**: Default is `enp0s5` on ARM64
2. **Firmware**: Must use EFI, not BIOS
3. **Boot Order**: Ensure CDROM is first for autoinstall

### Parallels Tools Integration

For autoinstall:
```yaml
packages:
  - build-essential
  - linux-headers-generic
  
late-commands:
  # Prepare for Parallels Tools installation
  - curtin in-target --target=/target -- apt-get install -y dkms
```

For cloud-init (post-install):
```yaml
#cloud-config
packages:
  - build-essential
  - linux-headers-virtual

runcmd:
  # Mount and install Parallels Tools
  - mount /dev/cdrom /mnt || true
  - /mnt/install --install-unattended-with-deps || true
  - umount /mnt || true
```

### Network Adapter Configuration

Parallels network modes:
- **Shared**: NAT with DHCP (default)
- **Bridged**: Direct connection to physical network
- **Host-Only**: Isolated network with host

### Disk Performance Optimization

```yaml
# In OpenTofu/Terraform configuration
resource "parallels-desktop_vm" "ubuntu" {
  config {
    disk_size = 51200  # 50GB
    
    # Performance optimizations
    disk_type = "expanding"  # or "plain" for pre-allocated
    
    # Hypervisor options
    hypervisor_type = "parallels"  # or "apple" on M1/M2
    nested_virtualization = false
    resource_quota = "unlimited"
  }
}
```

## OpenTofu/Terraform Configuration

### Provider Configuration

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.3.0"
    }
  }
}

provider "parallels-desktop" {
  # Provider configuration
  license_file = "~/.parallels/license.lic"
}
```

### Resource Configuration

```hcl
resource "parallels-desktop_vm" "ubuntu" {
  name        = var.vm_name
  description = "Ubuntu autoinstall VM"
  
  config {
    # Hardware
    cpu_count   = var.vm_cpus
    memory_size = var.vm_memory
    disk_size   = var.vm_disk_size
    
    # Boot configuration
    firmware_type = "efi"  # Required for ARM64
    boot_order   = "cdrom0,hdd0"
    
    # Display
    video_memory = 64
    resolution {
      width  = 1920
      height = 1080
    }
    
    # Performance
    adaptive_hypervisor = true
    hypervisor_type    = "parallels"
    nested_virtualization = false
    
    # Time sync
    time_sync = "host"
  }
  
  # ISO attachment
  cdrom {
    iso_path  = var.iso_path
    connected = true
  }
  
  # Network
  network_adapter {
    mode = "shared"  # or "bridged", "host_only"
  }
  
  # Advanced options
  on_destroy = "graceful_shutdown"
  timeout {
    create = "30m"
    stop   = "5m"
  }
}
```

### Dynamic Module Usage

```hcl
module "vm_deployment" {
  source = "./modules/parallels-vm"
  
  for_each = var.vm_definitions
  
  vm_name      = each.value.name
  vm_cpus      = each.value.cpus
  vm_memory    = each.value.memory
  vm_disk_size = each.value.disk_size
  iso_path     = each.value.iso_path
  
  # Dependencies
  depends_on = [
    module.vm_deployment[each.value.depends_on]
  ]
}
```

## Security Implementation

### Password Security

Generate secure password hashes:
```bash
# Using OpenSSL (SHA-512)
openssl passwd -6 -salt $(openssl rand -base64 16) "YourPassword"

# Using mkpasswd
mkpasswd -m sha-512 -S $(pwgen -ns 16 1) "YourPassword"

# Using Python
python3 -c 'import crypt,getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))'
```

### SSH Key Management

```yaml
ssh:
  install-server: true
  allow-pw: false  # Disable password authentication
  authorized-keys:
    - "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
```

### Firewall Configuration

```yaml
late-commands:
  # Configure UFW
  - curtin in-target --target=/target -- ufw default deny incoming
  - curtin in-target --target=/target -- ufw default allow outgoing
  - curtin in-target --target=/target -- ufw allow ssh
  - curtin in-target --target=/target -- ufw limit ssh/tcp comment 'Rate limit SSH'
  - curtin in-target --target=/target -- ufw --force enable
```

### Kernel Security Parameters

```yaml
write_files:
  - path: /etc/sysctl.d/99-security.conf
    content: |
      # IP Spoofing protection
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.conf.default.rp_filter = 1
      
      # Ignore ICMP redirects
      net.ipv4.conf.all.accept_redirects = 0
      net.ipv6.conf.all.accept_redirects = 0
      
      # Ignore send redirects
      net.ipv4.conf.all.send_redirects = 0
      
      # Disable source packet routing
      net.ipv4.conf.all.accept_source_route = 0
      net.ipv6.conf.all.accept_source_route = 0
      
      # Log Martians
      net.ipv4.conf.all.log_martians = 1
      
      # Ignore ICMP ping requests
      net.ipv4.icmp_echo_ignore_broadcasts = 1
      
      # Disable IPv6
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
```

### Audit Configuration

```yaml
packages:
  - auditd
  - aide

late-commands:
  # Configure auditd
  - curtin in-target --target=/target -- systemctl enable auditd
  
  # Initialize AIDE
  - curtin in-target --target=/target -- aideinit
  - curtin in-target --target=/target -- mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

## Performance Optimization

### Installation Performance

```yaml
autoinstall:
  # Use local mirror
  apt:
    primary:
      - arches: [arm64]
        uri: "http://local-mirror.example.com/ubuntu"
    
    # Disable security updates during install
    disable_suites:
      - security
      - updates
      
  # Minimize installed packages
  packages:
    - ubuntu-minimal
    - openssh-server
    - qemu-guest-agent
```

### Disk I/O Optimization

```yaml
storage:
  config:
    - type: disk
      id: disk-sda
      path: /dev/sda
      
    # Align partitions for SSDs
    - type: partition
      id: partition-root
      device: disk-sda
      size: -1
      offset: 1048576  # 1MB alignment
      
    # Optimize filesystem
    - type: format
      id: format-root
      volume: partition-root
      fstype: ext4
      # Mount options for performance
      mount_options: 'noatime,nodiratime,errors=remount-ro'
```

### Network Performance

```yaml
write_files:
  - path: /etc/sysctl.d/99-network-performance.conf
    content: |
      # Increase network buffer sizes
      net.core.rmem_max = 134217728
      net.core.wmem_max = 134217728
      net.ipv4.tcp_rmem = 4096 87380 134217728
      net.ipv4.tcp_wmem = 4096 65536 134217728
      
      # Enable TCP Fast Open
      net.ipv4.tcp_fastopen = 3
      
      # Optimize for low latency
      net.ipv4.tcp_low_latency = 1
```

## Advanced Configurations

### Custom Kernel Parameters

```yaml
autoinstall:
  kernel:
    package: linux-generic-hwe-22.04
    
  # Boot parameters
  kernel_cmdline:
    default: "quiet splash"
    extra: "mitigations=auto intel_idle.max_cstate=1"
```

### Complex User Configuration

```yaml
users:
  - name: admin
    gecos: System Administrator
    groups: [sudo, adm, cdrom, dip, plugdev, lxd]
    shell: /bin/bash
    lock_passwd: false
    passwd: "$6$rounds=4096$..."
    sudo: ALL=(ALL:ALL) ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...
      
  - name: appuser
    gecos: Application User
    groups: [docker]
    shell: /bin/bash
    lock_passwd: true
    sudo: false
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3...
```

### Proxy Configuration

```yaml
autoinstall:
  proxy: http://proxy.example.com:3128/
  
  apt:
    proxy: http://proxy.example.com:3128/
    
write_files:
  - path: /etc/environment
    append: true
    content: |
      http_proxy="http://proxy.example.com:3128/"
      https_proxy="http://proxy.example.com:3128/"
      no_proxy="localhost,127.0.0.1,.example.com"
```

### Conditional Configuration

Using Jinja2 templating:
```yaml
## template: jinja
#cloud-config
autoinstall:
  version: 1
  
  network:
    ethernets:
      {{ primary_interface }}:
        {% if static_ip is defined %}
        addresses:
          - {{ static_ip }}/{{ subnet_mask }}
        gateway4: {{ gateway }}
        {% else %}
        dhcp4: true
        {% endif %}
```

### Debugging and Logging

```yaml
autoinstall:
  # Enable debug mode
  reporting:
    builtin:
      type: print
      level: DEBUG
      
  # Log all commands
  early-commands:
    - exec > >(tee /var/log/early-commands.log)
    - exec 2>&1
    - set -x
    
  late-commands:
    - exec > >(tee /target/var/log/late-commands.log)
    - exec 2>&1
    - set -x
```

## Validation and Testing

### Pre-deployment Validation

```bash
# Validate YAML syntax
python3 -m yaml < user-data

# Validate cloud-config
cloud-init devel schema --config-file user-data

# Check autoinstall schema
cloud-init devel schema -m cc_autoinstall --annotate

# Security audit
grep -E "(password|passwd):[[:space:]]*['\"]?[^$]" user-data && echo "WARNING: Plaintext password found"
```

### Post-deployment Verification

```bash
# Check installation logs
sudo cat /var/log/installer/autoinstall-user-data
sudo cat /var/log/installer/subiquity-server-debug.log
sudo cat /var/log/installer/curtin-install.log

# Verify cloud-init completion
cloud-init status --wait

# Check for errors
sudo journalctl -u cloud-init --no-pager | grep -i error
```

This technical reference provides the deep technical details needed to understand and implement Ubuntu autoinstall configurations with Parallels Desktop. For practical examples and use cases, refer to the [Deployment Methods Guide](deployment-methods.md).