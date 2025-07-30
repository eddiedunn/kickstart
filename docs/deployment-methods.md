# Deployment Methods Guide

This comprehensive guide covers all available methods for deploying Ubuntu VMs on Parallels Desktop, helping you choose the right approach for your specific needs.

## Overview

This project supports three primary deployment methods:

1. **ISO-based Autoinstall** - Traditional method using custom Ubuntu ISOs with embedded autoinstall
2. **Template-based Cloning** - Fast deployment from pre-configured VM templates  
3. **Hybrid Cloud-Init** - Dynamic configuration that works with both methods

## Quick Decision Guide

Choose your deployment method based on these criteria:

```
┌─────────────────────────────────────┐
│   What are you trying to achieve?   │
└─────────────────┬───────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │                           │
    ▼                           ▼
┌─────────────────┐     ┌──────────────────┐
│ Fresh Install   │     │ Quick Deployment │
│ from Scratch    │     │ of Multiple VMs  │
└────────┬────────┘     └────────┬─────────┘
         │                       │
         ▼                       ▼
  ISO Autoinstall         Template Cloning
```

### Use ISO-based Autoinstall When:
- Starting fresh with latest Ubuntu version
- Creating the initial "golden image"
- Need specific installation-time configurations
- Building for CI/CD pipelines
- Compliance requires installation from trusted media

### Use Template-based Cloning When:
- Deploying multiple similar VMs quickly
- Development/testing environments
- POC or demo environments
- Need consistent pre-installed software
- Want to save time and disk space

### Use Cloud-Init for:
- Post-boot customization (both methods)
- Dynamic hostname and network configuration
- SSH key injection
- Package installation
- User creation and configuration

## Method 1: ISO-based Autoinstall

### Overview
Creates VMs from scratch using a custom Ubuntu ISO with embedded autoinstall configuration. This method provides complete control over the installation process and ensures consistency from a known base.

### How It Works
1. Build custom ISO with autoinstall configuration
2. OpenTofu creates VM and attaches ISO
3. VM boots and runs unattended installation
4. Cloud-init runs on first boot for customization

### Setup Steps

#### Step 1: Build Custom ISO
```bash
# Navigate to project directory
cd /Users/gdunn6/code/eddiedunn/kickstart

# Build autoinstall ISO with your SSH keys
./scripts/build-autoinstall-iso.sh /path/to/ubuntu-22.04.5-live-server-arm64.iso

# The script will:
# - Detect ISO version and architecture
# - Let you select SSH keys from ~/.ssh
# - Create ISO in output/ directory
```

#### Step 2: Configure OpenTofu
```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your settings
vim terraform.tfvars
```

#### Step 3: Deploy VMs
```bash
# Initialize OpenTofu
tofu init

# Review deployment plan
tofu plan

# Deploy VMs
tofu apply
```

### Configuration Examples

#### Single VM Deployment
```hcl
# terraform.tfvars
default_iso_path = "../output/ubuntu-autoinstall.iso"
vm_name          = "ubuntu-server"
vm_cpus          = 4
vm_memory        = 4096
vm_disk_size     = 50
```

#### Multiple VM Deployment
```hcl
# terraform.tfvars
vm_definitions = {
  "web-server" = {
    name      = "ubuntu-web-01"
    iso_path  = "../output/ubuntu-autoinstall.iso"
    cpus      = 2
    memory    = 2048
    disk_size = 30
  }
  "database" = {
    name      = "ubuntu-db-01"
    iso_path  = "../output/ubuntu-autoinstall.iso"
    cpus      = 4
    memory    = 8192
    disk_size = 100
  }
}
```

### Autoinstall Configuration Details

The autoinstall configuration includes:
- Automatic installation with no prompts
- Network configuration (DHCP by default)
- Storage layout (LVM on entire disk)
- User creation with SSH keys
- Package selection
- Post-installation commands

Example autoinstall snippet:
```yaml
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    ethernets:
      enp0s5:
        dhcp4: true
  storage:
    layout:
      name: lvm
  identity:
    hostname: ubuntu-server
    username: ubuntu
    password: "$6$rounds=4096$..."
  ssh:
    install-server: true
    allow-pw: false
```

### Pros
- Always latest OS version
- Complete control over installation
- Reproducible from source
- No dependency on existing VMs
- Suitable for production deployments
- Best for compliance requirements

### Cons
- Slower (15-20 minutes per VM)
- More resource intensive during installation
- Requires ISO rebuild for configuration changes
- Not ideal for rapid iteration

## Method 2: Template-based Cloning

### Overview
Rapidly deploy VMs by cloning from pre-configured templates. This method provides the fastest deployment times and is ideal for development and testing scenarios.

### Template Types

#### 2.1 Linked Clone Templates
Linked clones share base disk with parent, only storing differences.
- **Speed**: < 1 minute deployment
- **Space**: ~10% of full VM size
- **Use case**: Development environments

#### 2.2 Full Clone Templates
Complete copy of template VM.
- **Speed**: 2-3 minutes deployment
- **Space**: Full VM size
- **Use case**: Isolated environments

#### 2.3 PVM Bundle Templates
Portable VM packages that can be shared between hosts.
- **Speed**: 3-5 minutes deployment
- **Space**: Compressed VM size
- **Use case**: Template distribution

#### 2.4 Snapshot-based Templates
Point-in-time VM state capture.
- **Speed**: 1-2 minutes deployment
- **Space**: Differential storage
- **Use case**: Version management

### Creating Templates

#### Step 1: Prepare Base VM
Deploy and configure a base VM using ISO method or manually:
```bash
# Option 1: Deploy from ISO
./scripts/deploy-vm.sh output/ubuntu-autoinstall.iso ubuntu-base

# Option 2: Use existing VM
# Ensure VM has all required software installed
```

#### Step 2: Configure Base VM
```bash
# SSH into VM
ssh ubuntu@<vm-ip>

# Update and install software
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git vim htop build-essential

# Install any role-specific software
# Configure system settings
# Install and configure Parallels Tools
```

#### Step 3: Prepare for Templating
```bash
# Run preparation script (from host)
./scripts/prepare-vm-template.sh ubuntu-base

# This will:
# - Clean package caches
# - Remove SSH host keys
# - Clear logs and temp files
# - Reset machine IDs
# - Prepare cloud-init
```

#### Step 4: Create Template
```bash
# Create all template types
./scripts/create-parallels-template.sh ubuntu-base all

# Or create specific type:
./scripts/create-parallels-template.sh ubuntu-base template  # Linked clone
./scripts/create-parallels-template.sh ubuntu-base export    # PVM bundle
./scripts/create-parallels-template.sh ubuntu-base snapshot  # Snapshot
```

### Template Management

#### List Available Templates
```bash
# Using management script
./scripts/manage-templates.sh list-templates

# Using Parallels CLI
prlctl list -t
```

#### Clone Templates Manually
```bash
# Linked clone (fast, space-efficient)
./scripts/manage-templates.sh clone ubuntu-base-template --name dev-vm --linked

# Full clone
./scripts/manage-templates.sh clone ubuntu-base-template --name prod-vm
```

#### Export/Import Templates
```bash
# Export template as PVM
./scripts/manage-templates.sh export-pvm --name ubuntu-base --file ubuntu-base.pvm

# Import PVM as template
./scripts/manage-templates.sh import-pvm --file ubuntu-base.pvm
```

### OpenTofu Configuration for Templates

#### Basic Template Deployment
```hcl
# terraform.tfvars
vm_template_definitions = {
  "web-server" = {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cpus         = 2
    memory       = 4096
  }
}
```

#### PVM Bundle Deployment
```hcl
vm_template_definitions = {
  "imported-vm" = {
    source_type = "pvm"
    source_name = "./templates/ubuntu-configured.pvm"
    cpus        = 2
    memory      = 4096
  }
}
```

#### Snapshot-based Deployment
```hcl
vm_template_definitions = {
  "from-snapshot" = {
    source_type = "snapshot"
    source_name = "clean-state"
    source_vm   = "ubuntu-template"
  }
}
```

### Template Best Practices

1. **Version Control**: Use semantic versioning (e.g., ubuntu-22.04-v1.2)
2. **Documentation**: Maintain changelog for each template
3. **Regular Updates**: Update templates monthly for security patches
4. **Minimal Base**: Keep templates lean, use cloud-init for customization
5. **Testing**: Always test template deployment before production use

### Pros
- Very fast deployment (< 1 minute with linked clones)
- Disk space efficient
- Pre-installed software included
- Consistent environment
- Ideal for development/testing
- Perfect for CI/CD environments

### Cons
- Requires maintaining templates
- Templates can become outdated
- Initial template creation time
- Not suitable for fresh installs
- Linked clones depend on parent template

## Method 3: Cloud-Init Integration

### Overview
Cloud-init provides dynamic, post-boot configuration for VMs regardless of deployment method. It runs on first boot to customize the VM based on provided configuration.

### Cloud-Init with ISO Deployment

When using ISO-based deployment, cloud-init configuration can be:
1. Embedded in the ISO (NoCloud datasource)
2. Provided via separate cloud-init ISO
3. Fetched from network datasource

Example embedded configuration:
```yaml
#cloud-config
autoinstall:
  version: 1
  # Installation configuration
  
# Cloud-init user-data (runs after install)
hostname: web-server
fqdn: web-server.local
manage_etc_hosts: true

users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...
```

### Cloud-Init with Template Deployment

Templates must have cloud-init installed and cleaned:
```bash
# In template preparation
sudo cloud-init clean --logs
```

OpenTofu configuration with cloud-init:
```hcl
vm_template_definitions = {
  "web" = {
    source_type = "template"
    source_name = "ubuntu-base"
    cloud_init  = true
    cloud_init_files = {
      user_data = "./cloud-init/web-server.yaml"
      meta_data = "./cloud-init/meta-data.yaml"
    }
  }
}
```

### Cloud-Init Configuration Examples

#### Basic Configuration
```yaml
#cloud-config
hostname: my-server
fqdn: my-server.example.com
manage_etc_hosts: true

packages:
  - nginx
  - postgresql
  - python3-pip

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
```

#### Advanced Configuration
```yaml
#cloud-config
# User creation
users:
  - default
  - name: appuser
    groups: [docker, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...

# Network configuration
network:
  version: 2
  ethernets:
    enp0s5:
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]

# File creation
write_files:
  - path: /etc/nginx/sites-available/app
    content: |
      server {
        listen 80;
        server_name app.local;
        root /var/www/app;
      }

# Package installation and configuration
packages:
  - docker.io
  - docker-compose

# Commands to run
runcmd:
  - usermod -aG docker ubuntu
  - systemctl enable docker
  - docker pull nginx:latest
```

### Cloud-Init Best Practices

1. **Keep it Simple**: Focus on initial configuration, use configuration management for complex setups
2. **Idempotency**: Ensure configurations can run multiple times safely
3. **Error Handling**: Add error checking to runcmd scripts
4. **Logging**: Check `/var/log/cloud-init.log` for troubleshooting
5. **Validation**: Test configurations with `cloud-init devel schema`

## Use Case Scenarios

### Scenario 1: Production Web Farm
**Recommended: ISO-based for initial setup, then templates**

```bash
# 1. Build golden image from ISO
./scripts/build-autoinstall-iso.sh ubuntu-22.04-server.iso
tofu apply -var-file=golden-image.tfvars

# 2. Configure and convert to template
./scripts/prepare-vm-template.sh ubuntu-golden
./scripts/create-parallels-template.sh ubuntu-golden template

# 3. Deploy web servers from template
tofu apply -var-file=web-farm.tfvars
```

### Scenario 2: Development Environment
**Recommended: Template-based with linked clones**

```hcl
# dev-environment.tfvars
vm_template_definitions = {
  for i in range(1, 6) : "dev-${i}" => {
    source_type  = "template"
    source_name  = "ubuntu-dev-template"
    linked_clone = true  # Save disk space
    cpus         = 2
    memory       = 4096
    cloud_init   = true
    cloud_init_files = {
      user_data = templatefile("dev-init.yaml", {
        hostname = "dev-${i}"
        dev_num  = i
      })
    }
  }
}
```

### Scenario 3: Kubernetes Cluster
**Recommended: Template + Cloud-Init for node customization**

```hcl
# k8s-cluster.tfvars
vm_template_definitions = {
  # Control plane nodes
  for i in range(1, 4) : "k8s-control-${i}" => {
    source_type = "template"
    source_name = "ubuntu-k8s-base"
    cpus        = 4
    memory      = 8192
    cloud_init_files = {
      user_data = templatefile("k8s-control.yaml", {
        node_name = "k8s-control-${i}"
        node_ip   = "192.168.1.${10 + i}"
      })
    }
  }
  
  # Worker nodes
  for i in range(1, 6) : "k8s-worker-${i}" => {
    source_type = "template"
    source_name = "ubuntu-k8s-base"
    cpus        = 4
    memory      = 16384
    cloud_init_files = {
      user_data = templatefile("k8s-worker.yaml", {
        node_name = "k8s-worker-${i}"
        node_ip   = "192.168.1.${20 + i}"
      })
    }
  }
}
```

### Scenario 4: CI/CD Pipeline Testing
**Recommended: ISO-based for reproducibility**

```yaml
# .gitlab-ci.yml
test_deployment:
  stage: test
  script:
    - ./scripts/build-autoinstall-iso.sh $BASE_ISO
    - cd opentofu
    - tofu init
    - tofu apply -auto-approve -var-file=ci-test.tfvars
    - ./run-integration-tests.sh
    - tofu destroy -auto-approve
```

## Performance Comparison

| Method | Initial Setup Time | Per VM Deployment | Disk Usage | Best For |
|--------|-------------------|-------------------|------------|----------|
| ISO Autoinstall | 5 min (ISO build) | 15-20 min | Full size | Production, CI/CD |
| Template (Linked) | 20 min (template creation) | < 1 min | ~10% of full | Development, Testing |
| Template (Full) | 20 min | 2-3 min | Full size | Isolated environments |
| PVM Import | 20 min | 3-5 min | Full size | Cross-host deployment |
| Snapshot | 5 min | 1-2 min | Differential | Version testing |

## Migration Between Methods

### From ISO to Templates
1. Deploy initial VM using ISO method
2. Configure and update the VM as needed
3. Prepare for templating: `./scripts/prepare-vm-template.sh vm-name`
4. Create template: `./scripts/create-parallels-template.sh vm-name template`
5. Update terraform.tfvars to use template method
6. Test deployment with new template

### From Manual to Automated
1. Document current VM configuration
2. Create autoinstall or cloud-init configuration matching current setup
3. Test in isolated environment
4. Gradually migrate VMs using blue-green deployment

## Troubleshooting Common Issues

### ISO Boot Failures
```bash
# Verify ISO was built correctly
xorriso -indev output/ubuntu-*.iso -report_el_torito as_mkisofs

# Check UEFI settings in Parallels
prlctl list -i <vm-name> | grep -i boot

# Ensure firmware type is correct for architecture
# ARM64 requires EFI, not BIOS
```

### Template Clone Failures
```bash
# Verify template exists and is valid
prlctl list -t
prlctl check <template-name>

# Check available disk space
df -h

# Ensure template is not corrupted
# Try creating a new template if issues persist
```

### Cloud-Init Not Running
```bash
# Check cloud-init status inside VM
cloud-init status --long

# View cloud-init logs
sudo journalctl -u cloud-init
sudo cat /var/log/cloud-init.log

# Verify cloud-init datasource
cloud-init query -a

# Check if ISO is attached (for ISO-based cloud-init)
prlctl list -i <vm-name> | grep -i cdrom
```

### Network Configuration Issues
```bash
# Verify network adapter settings
prlctl list -i <vm-name> | grep -i network

# Check VM network configuration
prlctl exec <vm-name> "ip addr show"
prlctl exec <vm-name> "ip route show"

# Ensure Parallels network is functioning
prlsrvctl net list
```

## Security Considerations

### ISO-based Deployments
- Use encrypted passwords in autoinstall
- Embed only public SSH keys
- Enable firewall in late-commands
- Disable password authentication
- Keep ISOs in secure location

### Template-based Deployments
- Remove all credentials before creating templates
- Regenerate SSH host keys on first boot
- Use cloud-init to inject user-specific data
- Regularly update base templates
- Audit template access

### Cloud-Init Security
- Never include private keys or passwords
- Use hashed passwords only
- Validate cloud-init files before deployment
- Limit network datasource access
- Review runcmd scripts for security issues

## Next Steps

1. **Choose your deployment method** based on your use case
2. **Follow the setup steps** for your chosen method
3. **Test in a non-production environment** first
4. **Document your deployment process** for your team
5. **Automate repeated deployments** using the provided scripts

For additional details on specific topics:
- [Technical Reference](technical-reference.md) - Deep dive into configurations
- [Troubleshooting Guide](troubleshooting.md) - Comprehensive problem resolution
- [Cloud-Init Examples](../opentofu/cloud-init-examples/) - Ready-to-use configurations