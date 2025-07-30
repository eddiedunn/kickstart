# VM Template Guide for OpenTofu

This guide explains how to create and use VM templates with Parallels Desktop and OpenTofu for rapid deployment of multiple VMs.

## Overview

The template workflow allows you to:
- Create a base VM once with all required software
- Convert it to a reusable template
- Deploy multiple VMs from the template in seconds
- Customize each VM with cloud-init
- Save disk space with linked clones

## Quick Start

### 1. Prepare Your Base VM

First, ensure your base VM (`ubuntu-minimal-test`) is in a good state:

```bash
# Prepare the VM for templating (cleans caches, removes host keys, etc.)
./scripts/prepare-vm-template.sh ubuntu-minimal-test
```

### 2. Create Template

Convert the prepared VM to a template:

```bash
# Create all template formats (recommended)
./scripts/create-parallels-template.sh ubuntu-minimal-test all

# Or create specific format:
./scripts/create-parallels-template.sh ubuntu-minimal-test template  # Linked clone template
./scripts/create-parallels-template.sh ubuntu-minimal-test export    # PVM bundle
./scripts/create-parallels-template.sh ubuntu-minimal-test snapshot  # Snapshot
```

### 3. Deploy VMs with OpenTofu

```bash
cd opentofu

# Copy example configuration
cp terraform.tfvars.template-example terraform.tfvars

# Edit terraform.tfvars to:
# - Add your SSH public keys
# - Define the VMs you want to create
# - Customize cloud-init for each VM

# Initialize and deploy
tofu init
tofu apply
```

## Template Management

### List Templates
```bash
./scripts/manage-templates.sh list
```

### Get Template Info
```bash
./scripts/manage-templates.sh info ubuntu-minimal-test-template
```

### Clone Template Manually
```bash
# Full clone
./scripts/manage-templates.sh clone ubuntu-minimal-test-template --name test-vm

# Linked clone (saves space)
./scripts/manage-templates.sh clone ubuntu-minimal-test-template --name test-vm --linked
```

### Export/Import Templates
```bash
# Export template as PVM
./scripts/manage-templates.sh export ubuntu-minimal-test-template

# Import PVM as template
./scripts/manage-templates.sh import ./templates/ubuntu-template.pvm
```

## OpenTofu Configuration

### Basic Template Deployment

```hcl
template_vms = {
  "web-server" = {
    template_name = "ubuntu-minimal-test-template"
    cpus          = 2
    memory        = 4096
    linked_clone  = true
  }
}
```

### With Cloud-Init Customization

```hcl
template_vms = {
  "database" = {
    template_name = "ubuntu-minimal-test-template"
    cpus          = 4
    memory        = 8192
    linked_clone  = true
    cloud_init    = true
    user_data     = <<-EOF
      #cloud-config
      hostname: database
      packages:
        - postgresql
        - postgresql-contrib
      runcmd:
        - systemctl enable postgresql
        - systemctl start postgresql
    EOF
  }
}
```

### Deploy from PVM Bundle

```hcl
pvm_vms = {
  "imported-vm" = {
    pvm_path = "./templates/ubuntu-template-20240130.pvm"
    cpus     = 2
    memory   = 4096
  }
}
```

## Best Practices

### 1. Template Preparation
- Always run `prepare-vm-template.sh` before creating templates
- Ensure the VM has all base software installed
- Remove any sensitive data or credentials
- Install cloud-init for post-deployment customization

### 2. Storage Optimization
- Use linked clones for local development (90% space savings)
- Use PVM bundles for sharing templates between hosts
- Regular templates for production deployments

### 3. Cloud-Init Usage
- Keep user-data simple and focused
- Use for hostname, SSH keys, and initial packages
- Avoid complex configurations (use configuration management instead)

### 4. Version Control
- Create snapshots before major template updates
- Export PVM bundles for archival
- Document template contents and versions

## Troubleshooting

### VM Won't Start
- Check if template exists: `prlctl list -a -t`
- Verify linked clone base is available
- Check disk space for full clones

### Cloud-Init Not Working
- Ensure cloud-init is installed in the template
- Check if cloud-init ISO is attached: `prlctl list -i <vm-name>`
- Review cloud-init logs: `prlctl exec <vm-name> 'sudo cat /var/log/cloud-init.log'`

### IP Address Not Showing
- Wait for VM to fully boot (cloud-init can take 1-2 minutes)
- Check network configuration in Parallels
- Ensure QEMU guest agent is installed and running

## Example POC Deployment

For a typical proof-of-concept with web servers, database, and app servers:

```hcl
template_vms = {
  # Load balanced web servers
  "web-01" = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 2048 }
  "web-02" = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 2048 }
  "web-03" = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 2048 }
  
  # Database cluster
  "db-primary"   = { template_name = "ubuntu-minimal-test-template", cpus = 4, memory = 8192 }
  "db-secondary" = { template_name = "ubuntu-minimal-test-template", cpus = 4, memory = 8192 }
  
  # Application servers
  "app-01" = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 4096 }
  "app-02" = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 4096 }
  
  # Support services
  "cache"    = { template_name = "ubuntu-minimal-test-template", cpus = 2, memory = 4096 }
  "monitor"  = { template_name = "ubuntu-minimal-test-template", cpus = 1, memory = 2048 }
}
```

This creates 9 VMs in minutes, all from a single template!

## Clean Up

To remove all VMs:
```bash
tofu destroy
```

To remove a template:
```bash
./scripts/manage-templates.sh delete ubuntu-minimal-test-template
```