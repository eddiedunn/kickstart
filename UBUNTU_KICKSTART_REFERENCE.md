# Ubuntu Kickstart Technical Reference

Comprehensive technical reference for Ubuntu Kickstart automation using the Subiquity installer and cloud-init integration.

## Table of Contents

1. [Ubuntu Autoinstall Overview](#ubuntu-autoinstall-overview)
2. [Preseed vs Kickstart Differences](#preseed-vs-kickstart-differences)
3. [Cloud-init Integration](#cloud-init-integration)
4. [Core Directives Reference](#core-directives-reference)
5. [Network Configuration](#network-configuration)
6. [Storage Configuration](#storage-configuration)
7. [Package Management](#package-management)
8. [Advanced Configurations](#advanced-configurations)

## Ubuntu Autoinstall Overview

Ubuntu's modern approach to automated installation uses the Subiquity installer with cloud-init style configuration files. This is referred to as "autoinstall" and supports both cloud and bare-metal deployments.

### File Format

Ubuntu autoinstall uses YAML format with cloud-config headers:

```yaml
#cloud-config
autoinstall:
  version: 1
  # Configuration directives here
```

### Minimum Valid Configuration

```yaml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-server
    username: ubuntu
    password: "$6$exampleSalt$exampleHash"
  ssh:
    install-server: true
```

## Preseed vs Kickstart Differences

### Traditional Preseed (Debian Installer)

```bash
# Preseed format (legacy)
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain
```

### Modern Kickstart/Autoinstall (Subiquity)

```yaml
# Autoinstall format (modern)
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    ethernets:
      enp0s3:
        dhcp4: true
```

### Key Differences

| Feature | Preseed | Autoinstall |
|---------|---------|-------------|
| Format | Debconf | YAML |
| Installer | debian-installer | Subiquity |
| Ubuntu Support | All versions | 20.04+ |
| Cloud Integration | Limited | Native |
| Complexity | High | Medium |
| Flexibility | Maximum | High |
| Documentation | Extensive | Growing |

### Migration Example

```bash
# Convert preseed to autoinstall
# Preseed:
d-i partman-auto/method string lvm
d-i partman-auto-lvm/guided_size string max

# Autoinstall equivalent:
storage:
  layout:
    name: lvm
    sizing-policy: all
```

## Cloud-init Integration

### Datasource Configuration

```yaml
#cloud-config
autoinstall:
  version: 1
  # Autoinstall directives
  
# Cloud-init directives (post-install)
users:
  - name: clouduser
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - ssh-rsa AAAAB3NzaC1...

write_files:
  - path: /etc/motd
    content: |
      Welcome to Ubuntu Cloud Instance
      Deployed via Autoinstall + Cloud-init
```

### Merge Behavior

```yaml
#cloud-config
# These run during installation
autoinstall:
  late-commands:
    - echo "During installation" > /target/tmp/install.log

# These run on first boot
runcmd:
  - echo "First boot" > /tmp/firstboot.log
  - systemctl restart nginx
```

### Network Datasources

```yaml
# NoCloud datasource (local files)
autoinstall:
  network:
    version: 2
    ethernets:
      enp0s3:
        dhcp4: true

# EC2 datasource (AWS)
datasource:
  Ec2:
    metadata_urls: ['http://169.254.169.254']
    max_wait: 120
```

## Core Directives Reference

### Version Specification

```yaml
autoinstall:
  version: 1  # Required, currently only version 1
```

### Locale and Internationalization

```yaml
autoinstall:
  # Language and regional settings
  locale: en_US.UTF-8
  
  # Keyboard configuration
  keyboard:
    layout: us
    variant: ""       # Empty for default
    toggle: null      # Layout switching
    
  # Timezone
  timezone: America/New_York
  
  # Additional locale generation
  locale-gen:
    - en_GB.UTF-8
    - fr_FR.UTF-8
```

### System Identity

```yaml
autoinstall:
  identity:
    hostname: prod-web-01
    username: sysadmin
    realname: "System Administrator"
    password: "$6$rounds=4096$saltsalt$hash"  # mkpasswd -m sha-512
    
  # Alternative: encrypted password file
  identity:
    hostname: prod-web-01
    username: sysadmin
    password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      66383439383437366...
```

### Boot Configuration

```yaml
autoinstall:
  # Kernel parameters
  kernel:
    package: linux-generic-hwe-22.04
    
  # GRUB configuration
  grub:
    install_devices:
      - /dev/sda
    update_nvram: true
    probe_additional_os: false
    
  # Kernel command line
  kernel_cmdline:
    default: "quiet splash"
    extra: "mitigations=auto"
```

### Updates and Refresh

```yaml
autoinstall:
  # Refresh installer snap
  refresh-installer:
    update: yes
    channel: stable
    
  # Update system during install
  updates: security  # all, security, or none
  
  # Disable automatic updates
  apt:
    disable_components: [restricted, multiverse]
    geoip: false
```

## Network Configuration

### Basic DHCP Configuration

```yaml
autoinstall:
  network:
    version: 2
    renderer: networkd  # or NetworkManager
    ethernets:
      enp0s3:
        dhcp4: true
        dhcp6: false
        dhcp4-overrides:
          use-dns: true
          use-ntp: true
          use-hostname: false
```

### Static IP Configuration

```yaml
autoinstall:
  network:
    version: 2
    ethernets:
      enp0s3:
        addresses:
          - 192.168.1.100/24
        routes:
          - to: default
            via: 192.168.1.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
          search:
            - example.com
            - internal.example.com
```

### Bond Configuration

```yaml
autoinstall:
  network:
    version: 2
    ethernets:
      enp0s3:
        dhcp4: false
      enp0s4:
        dhcp4: false
    bonds:
      bond0:
        interfaces:
          - enp0s3
          - enp0s4
        parameters:
          mode: active-backup
          primary: enp0s3
          mii-monitor-interval: 100
        addresses:
          - 192.168.1.100/24
        routes:
          - to: default
            via: 192.168.1.1
```

### VLAN Configuration

```yaml
autoinstall:
  network:
    version: 2
    ethernets:
      enp0s3:
        dhcp4: false
    vlans:
      vlan10:
        id: 10
        link: enp0s3
        addresses:
          - 10.10.10.100/24
      vlan20:
        id: 20
        link: enp0s3
        addresses:
          - 10.20.20.100/24
```

### Bridge Configuration

```yaml
autoinstall:
  network:
    version: 2
    ethernets:
      enp0s3:
        dhcp4: false
    bridges:
      br0:
        interfaces:
          - enp0s3
        addresses:
          - 192.168.1.100/24
        parameters:
          stp: true
          forward-delay: 4
```

### WiFi Configuration

```yaml
autoinstall:
  network:
    version: 2
    wifis:
      wlan0:
        access-points:
          "CompanyWiFi":
            password: "SecurePassword123"
            auth:
              key-management: psk
        dhcp4: true
```

## Storage Configuration

### Simple Layouts

```yaml
autoinstall:
  storage:
    # Guided LVM with encryption
    layout:
      name: lvm
      encryption:
        passphrase: "DiskEncryptionPassphrase"
        
    # Direct layout (no LVM)
    layout:
      name: direct
      
    # Use entire disk
    sizing-policy: all
    
    # Reset partitions
    wipe: superblock-recursive
```

### Custom Partitioning

```yaml
autoinstall:
  storage:
    config:
      # Define disk
      - type: disk
        id: disk-sda
        path: /dev/sda
        wipe: superblock
        preserve: false
        name: ''
        grub_device: true
        
      # BIOS boot partition
      - type: partition
        id: partition-bios
        device: disk-sda
        size: 1MB
        flag: bios_grub
        
      # Boot partition
      - type: partition
        id: partition-boot
        device: disk-sda
        size: 1GB
        wipe: superblock
        flag: boot
        
      # Boot filesystem
      - type: format
        id: format-boot
        volume: partition-boot
        fstype: ext4
        
      # Root partition (remaining space)
      - type: partition
        id: partition-root
        device: disk-sda
        size: -1
        wipe: superblock
        
      # Root filesystem
      - type: format
        id: format-root
        volume: partition-root
        fstype: ext4
        
      # Mount points
      - type: mount
        id: mount-root
        device: format-root
        path: /
        
      - type: mount
        id: mount-boot
        device: format-boot
        path: /boot
```

### LVM Configuration

```yaml
autoinstall:
  storage:
    config:
      # Physical disk
      - type: disk
        id: disk-sda
        path: /dev/sda
        wipe: superblock
        preserve: false
        grub_device: true
        
      # Partition for LVM
      - type: partition
        id: partition-lvm
        device: disk-sda
        size: -1
        wipe: superblock
        
      # LVM physical volume
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
        
      # Filesystems
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
        
      # Mount points
      - type: mount
        id: mount-root
        device: format-root
        path: /
        
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
autoinstall:
  storage:
    config:
      # Two disks for RAID
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
        raidlevel: raid1
        devices:
          - part-sda1
          - part-sdb1
          
      # Format RAID
      - type: format
        id: format-raid
        volume: raid-1
        fstype: ext4
        
      # Mount RAID
      - type: mount
        id: mount-raid
        device: format-raid
        path: /
```

### ZFS Configuration

```yaml
autoinstall:
  storage:
    config:
      # Disk for ZFS
      - type: disk
        id: disk-sda
        path: /dev/sda
        wipe: superblock
        
      # ZFS pool
      - type: zpool
        id: zpool-rpool
        pool: rpool
        vdevs:
          - disk-sda
        mountpoint: /
        pool_properties:
          ashift: 12
        fs_properties:
          compression: lz4
          atime: off
          
      # ZFS datasets
      - type: zfs
        id: zfs-home
        pool: zpool-rpool
        volume: home
        properties:
          mountpoint: /home
          
      - type: zfs
        id: zfs-var
        pool: zpool-rpool
        volume: var
        properties:
          mountpoint: /var
```

## Package Management

### Package Selection

```yaml
autoinstall:
  # Minimal installation
  packages:
    - ubuntu-minimal
    - openssh-server
    
  # Full server installation
  packages:
    - ubuntu-server
    - build-essential
    - git
    - vim
    - htop
    
  # Remove packages (prefix with !)
  packages:
    - "!snap"
    - "!snapd"
    
  # Kernel selection
  kernel:
    package: linux-generic-hwe-22.04
    flavor: generic
```

### APT Configuration

```yaml
autoinstall:
  apt:
    # Don't update package lists during install
    disable_suites:
      - security
      - updates
      
    # Custom repositories
    sources:
      docker:
        source: "deb [arch=amd64] https://download.docker.com/linux/ubuntu $RELEASE stable"
        keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
        
    # APT preferences
    preferences:
      - package: "*"
        pin: "release a=noble-security"
        priority: 1000
        
    # Proxy configuration
    proxy: http://proxy.example.com:3128/
    https_proxy: http://proxy.example.com:3128/
```

### Snap Configuration

```yaml
autoinstall:
  # Install snaps
  snaps:
    - name: lxd
      channel: latest/stable
      
    - name: docker
      channel: latest/edge
      classic: true
      
    - name: microk8s
      channel: 1.28/stable
      classic: true
      
  # Snap assertions
  assertions:
    - |
      type: account-key
      authority-id: canonical
      ...
```

## Advanced Configurations

### Early Commands

```yaml
autoinstall:
  # Commands run before installation begins
  early-commands:
    - echo "Starting installation at $(date)" > /tmp/install.log
    - wget -O /tmp/custom-script.sh http://deploy.example.com/scripts/pre-install.sh
    - bash /tmp/custom-script.sh
```

### Late Commands

```yaml
autoinstall:
  # Commands run in the target system
  late-commands:
    # System configuration
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- systemctl disable bluetooth
    
    # User configuration
    - curtin in-target --target=/target -- usermod -aG docker ubuntu
    - curtin in-target --target=/target -- passwd -l root
    
    # Custom scripts
    - |
      cat <<'EOF' > /target/usr/local/bin/startup-script.sh
      #!/bin/bash
      echo "System initialized at $(date)" >> /var/log/startup.log
      EOF
    - curtin in-target --target=/target -- chmod +x /usr/local/bin/startup-script.sh
    
    # Service configuration
    - |
      cat <<'EOF' > /target/etc/systemd/system/custom.service
      [Unit]
      Description=Custom Startup Service
      After=network.target
      
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/startup-script.sh
      RemainAfterExit=yes
      
      [Install]
      WantedBy=multi-user.target
      EOF
    - curtin in-target --target=/target -- systemctl enable custom.service
```

### Error Commands

```yaml
autoinstall:
  # Commands run on installation failure
  error-commands:
    - tar czf /tmp/install-logs.tar.gz /var/log/installer/
    - curl -X POST -F "file=@/tmp/install-logs.tar.gz" http://logs.example.com/upload
    - echo "Installation failed at $(date)" | mail -s "Install Failure" admin@example.com
```

### Reporting Configuration

```yaml
autoinstall:
  # Progress reporting
  reporting:
    hook:
      type: webhook
      endpoint: http://deploy.example.com/api/progress
      level: INFO
      
    syslog:
      type: syslog
      endpoint: syslog://logs.example.com:514
      
    # Console output
    builtin:
      type: print
```

### User Data Integration

```yaml
#cloud-config
# Merged with autoinstall configuration
autoinstall:
  version: 1
  # Installation configuration

# Cloud-init user-data (runs after install)
users:
  - name: deploy
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    
write_files:
  - path: /etc/docker/daemon.json
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        }
      }
      
runcmd:
  - systemctl restart docker
  - docker pull nginx:latest
```

### Proxy Configuration

```yaml
autoinstall:
  proxy: http://proxy.example.com:3128/
  
  # APT proxy
  apt:
    proxy: http://proxy.example.com:3128/
    
  # Environment variables
  late-commands:
    - |
      cat <<'EOF' >> /target/etc/environment
      http_proxy="http://proxy.example.com:3128/"
      https_proxy="http://proxy.example.com:3128/"
      no_proxy="localhost,127.0.0.1,.example.com"
      EOF
```

### Debugging Configuration

```yaml
autoinstall:
  # Enable debug mode
  version: 1
  refresh-installer:
    update: yes
    
  # Interactive sections for debugging
  interactive-sections:
    - storage
    - network
    
  # Verbose logging
  reporting:
    builtin:
      type: print
      level: DEBUG
```

## Validation and Testing

### Schema Validation

```bash
# Validate autoinstall configuration
cloud-init devel schema --config-file autoinstall.yaml

# Check specific module
cloud-init devel schema -m cc_autoinstall --annotate
```

### Dry Run Testing

```yaml
# Test configuration without installing
autoinstall:
  version: 1
  # Set interactive mode for testing
  interactive-sections:
    - "*"
```

### Integration with CI/CD

```yaml
# GitLab CI example
validate:autoinstall:
  stage: test
  script:
    - apt-get update && apt-get install -y cloud-init
    - cloud-init devel schema --config-file $CI_PROJECT_DIR/autoinstall.yaml
    - python3 scripts/validate-network-config.py
    - python3 scripts/validate-storage-config.py
```

## Common Patterns and Examples

### Multi-disk Server Configuration

```yaml
#cloud-config
autoinstall:
  version: 1
  storage:
    config:
      # OS disk (SSD)
      - type: disk
        id: disk-sda
        path: /dev/sda
        wipe: superblock
        
      # Data disks (HDDs)
      - type: disk
        id: disk-sdb
        path: /dev/sdb
        wipe: superblock
        
      - type: disk
        id: disk-sdc
        path: /dev/sdc
        wipe: superblock
        
      # OS partitions on SSD
      - type: partition
        id: part-boot
        device: disk-sda
        size: 1GB
        flag: boot
        
      - type: partition
        id: part-root
        device: disk-sda
        size: 50GB
        
      # Data partitions for RAID
      - type: partition
        id: part-data1
        device: disk-sdb
        size: -1
        
      - type: partition
        id: part-data2
        device: disk-sdc
        size: -1
        
      # RAID for data
      - type: raid
        id: raid-data
        name: md0
        raidlevel: raid1
        devices:
          - part-data1
          - part-data2
```

### Cloud-Optimized Configuration

```yaml
#cloud-config
autoinstall:
  version: 1
  
  # Minimal cloud instance
  packages:
    - cloud-init
    - cloud-guest-utils
    - cloud-initramfs-growroot
    
  # Cloud-specific storage
  storage:
    layout:
      name: direct
      match:
        size: smallest
        
  # Cloud networking
  network:
    version: 2
    ethernets:
      id0:
        match:
          name: en*
        dhcp4: true
        dhcp4-overrides:
          use-hostname: true
```

## Troubleshooting

### Common Issues and Solutions

1. **Network Configuration Not Applied**
   ```yaml
   # Ensure network version is specified
   network:
     version: 2  # Required
   ```

2. **Storage Configuration Fails**
   ```yaml
   # Check disk paths exist
   early-commands:
     - lsblk
     - ls -la /dev/disk/by-id/
   ```

3. **Package Installation Errors**
   ```yaml
   # Enable universe repository
   apt:
     disable_components: []  # Enable all components
   ```

### Debug Output Locations

- Installation logs: `/var/log/installer/`
- Cloud-init logs: `/var/log/cloud-init.log`
- Subiquity logs: `/var/log/installer/subiquity-server-debug.log`
- Curtin logs: `/var/log/installer/curtin-install.log`

This reference provides comprehensive coverage of Ubuntu Kickstart/Autoinstall capabilities. For the latest updates and additional features, consult the official Ubuntu Server documentation.