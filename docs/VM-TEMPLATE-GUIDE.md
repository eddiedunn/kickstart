# VM Template Guide

This comprehensive guide covers creating, managing, and deploying VM templates with Parallels Desktop and OpenTofu.

## Overview

VM templates provide a fast, efficient way to deploy multiple VMs with consistent configurations. This guide covers:
- Creating templates from existing VMs
- Managing different template types
- Deploying VMs using OpenTofu
- Best practices and troubleshooting

## Template Types

### 1. Linked Clone Templates
**Best for:** Development environments, rapid deployment
- **Speed:** < 1 minute deployment
- **Space:** ~10% of original VM size
- **Limitation:** Requires parent template to remain intact

### 2. Full Clone Templates
**Best for:** Independent VMs, production use
- **Speed:** 2-3 minutes deployment
- **Space:** Full VM size
- **Benefit:** Completely independent from parent

### 3. PVM Bundle Templates
**Best for:** Template distribution, archival
- **Speed:** 3-5 minutes deployment
- **Space:** Compressed VM size
- **Benefit:** Portable between hosts

### 4. Snapshot Templates
**Best for:** Version control, testing
- **Speed:** 1-2 minutes deployment
- **Space:** Differential storage
- **Benefit:** Multiple restore points

## Creating Templates

### Step 1: Prepare Base VM

First, deploy and configure a base VM:

```bash
# Option 1: Deploy from ISO
./scripts/build-autoinstall-iso.sh ubuntu-22.04.iso
cd opentofu && tofu apply

# Option 2: Use existing VM
# Ensure VM has all required software installed
```

Configure the base VM:
```bash
# SSH into VM
ssh ubuntu@<vm-ip>

# Update and install base software
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  curl wget git vim htop \
  build-essential python3-pip \
  docker.io docker-compose

# Configure as needed
# Install role-specific software
# Set up configurations
```

### Step 2: Install Parallels Tools

For optimal performance:
```bash
# From Parallels Desktop menu: Actions > Install Parallels Tools
# In VM:
sudo mount /dev/cdrom /mnt
sudo /mnt/install
# Reboot when prompted
```

### Step 3: Prepare for Templating

Clean and generalize the VM:
```bash
# Run preparation script (from host)
./scripts/prepare-vm-template.sh ubuntu-base

# This script:
# - Cleans package caches
# - Removes SSH host keys
# - Clears machine IDs
# - Resets cloud-init
# - Removes logs and temp files
# - Prepares for first boot
```

### Step 4: Create Template

Convert VM to template:
```bash
# Create all template types (recommended)
./scripts/create-parallels-template.sh ubuntu-base all

# Or create specific type:
./scripts/create-parallels-template.sh ubuntu-base template  # Linked clone
./scripts/create-parallels-template.sh ubuntu-base export    # PVM bundle
./scripts/create-parallels-template.sh ubuntu-base snapshot  # Snapshot
```

## Template Management

### List Templates
```bash
# Using management script
./scripts/manage-templates.sh list-templates

# Using Parallels CLI
prlctl list -t

# Get template details
./scripts/manage-templates.sh info ubuntu-base-template
```

### Clone Templates Manually
```bash
# Linked clone (fast, space-efficient)
./scripts/manage-templates.sh clone ubuntu-base-template \
  --name dev-vm --linked

# Full clone (independent copy)
./scripts/manage-templates.sh clone ubuntu-base-template \
  --name prod-vm
```

### Export/Import Templates
```bash
# Export template as PVM bundle
./scripts/manage-templates.sh export-pvm \
  --name ubuntu-base-template \
  --file ubuntu-base-v1.0.pvm

# Import PVM as template
./scripts/manage-templates.sh import-pvm \
  --file ubuntu-base-v1.0.pvm
```

### Update Templates
```bash
# 1. Clone template to working VM
prlctl clone ubuntu-base-template --name update-vm

# 2. Start and update
prlctl start update-vm
ssh ubuntu@<vm-ip>
sudo apt update && sudo apt upgrade -y

# 3. Re-prepare and create new version
./scripts/prepare-vm-template.sh update-vm
./scripts/create-parallels-template.sh update-vm template

# 4. Version the template
prlctl set update-vm-template \
  --name ubuntu-base-template-v2
```

## OpenTofu Deployment

### Basic Configuration

Deploy VMs from templates using OpenTofu:

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

### Advanced Configuration with Cloud-Init

```hcl
vm_template_definitions = {
  "app-server" = {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cpus         = 4
    memory       = 8192
    
    # Cloud-init configuration
    cloud_init = true
    cloud_init_files = {
      user_data = "./cloud-init/app-server.yaml"
      meta_data = "./cloud-init/meta-data.yaml"
    }
    
    # Direct cloud-init data
    customize = {
      hostname = "app-server-01"
      packages = ["nginx", "postgresql"]
      runcmd   = [
        "systemctl enable nginx",
        "systemctl start nginx"
      ]
    }
  }
}
```

### Deploy from PVM Bundles

```hcl
vm_template_definitions = {
  "imported-vm" = {
    source_type = "pvm"
    source_name = "./templates/ubuntu-base-v1.0.pvm"
    cpus        = 2
    memory      = 4096
  }
}
```

### Deploy from Snapshots

```hcl
vm_template_definitions = {
  "test-vm" = {
    source_type = "snapshot"
    source_name = "baseline-config"
    source_vm   = "ubuntu-base-template"
  }
}
```

## Cloud-Init Integration

### Basic Cloud-Init Configuration

Create `cloud-init/web-server.yaml`:
```yaml
#cloud-config
hostname: web-server
fqdn: web-server.local
manage_etc_hosts: true

users:
  - default
  - name: webadmin
    groups: [sudo, www-data]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...

packages:
  - nginx
  - certbot
  - python3-certbot-nginx

write_files:
  - path: /etc/nginx/sites-available/default
    content: |
      server {
        listen 80 default_server;
        root /var/www/html;
        index index.html;
      }

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - ufw allow 'Nginx Full'
```

### Dynamic Configuration

Use Terraform templates for dynamic cloud-init:
```hcl
# In terraform.tfvars
vm_template_definitions = {
  for i in range(1, 4) : "web-${i}" => {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cloud_init   = true
    cloud_init_files = {
      user_data = templatefile("cloud-init/web.yaml", {
        hostname   = "web-${i}"
        node_id    = i
        cluster_ip = "192.168.1.${10 + i}"
      })
    }
  }
}
```

## Best Practices

### 1. Template Versioning
- Use semantic versioning: `ubuntu-base-v1.2.3`
- Include date stamps: `ubuntu-base-20240130`
- Document changes in changelog

### 2. Template Maintenance
- Update monthly for security patches
- Test updates before production use
- Keep previous version until new one is proven
- Automate update process where possible

### 3. Security Considerations
- Never include:
  - Private SSH keys
  - Passwords or secrets
  - Production certificates
  - Customer data
- Always regenerate on first boot:
  - SSH host keys
  - Machine IDs
  - Network MAC addresses

### 4. Storage Optimization
- Use linked clones for development
- Regular templates for production
- PVM bundles for archival
- Clean up old templates regularly

### 5. Documentation
- Document what's installed in each template
- List any manual configuration steps
- Note any known issues or limitations
- Include contact information for support

## Pre-Template Checklist

Before creating a template, ensure the VM is properly generalized:

- [ ] Package manager cache cleared (`apt-get clean`)
- [ ] SSH host keys removed (`/etc/ssh/ssh_host_*`)
- [ ] Machine ID cleared (`/etc/machine-id`)
- [ ] Cloud-init data cleaned (`cloud-init clean`)
- [ ] Network configs reset
- [ ] Logs cleared
- [ ] Temporary files removed
- [ ] User history cleared
- [ ] Free space zeroed (optional, for compression)

## Use Case Examples

### Development Environment
```hcl
# Deploy 5 developer workstations
vm_template_definitions = {
  for i in range(1, 6) : "dev-${i}" => {
    source_type  = "template"
    source_name  = "ubuntu-dev-template"
    linked_clone = true  # Save space
    cpus         = 4
    memory       = 8192
    cloud_init_files = {
      user_data = templatefile("cloud-init/dev.yaml", {
        developer_id = i
        username     = "developer${i}"
      })
    }
  }
}
```

### Web Application Stack
```hcl
# Deploy complete application environment
vm_template_definitions = {
  # Load balancer
  "lb" = {
    source_type = "template"
    source_name = "ubuntu-base-template"
    cpus        = 2
    memory      = 2048
    cloud_init_files = {
      user_data = "./cloud-init/haproxy.yaml"
    }
  }
  
  # Web servers
  for i in range(1, 4) : "web-${i}" => {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cpus         = 2
    memory       = 4096
    cloud_init_files = {
      user_data = "./cloud-init/nginx.yaml"
    }
  }
  
  # Database
  "db-primary" = {
    source_type = "template"
    source_name = "ubuntu-base-template"
    cpus        = 4
    memory      = 8192
    cloud_init_files = {
      user_data = "./cloud-init/postgresql.yaml"
    }
  }
}
```

### POC Deployment
```hcl
template_vms = {
  # Load balanced web servers
  "web-01" = { template_name = "ubuntu-base", cpus = 2, memory = 2048 }
  "web-02" = { template_name = "ubuntu-base", cpus = 2, memory = 2048 }
  "web-03" = { template_name = "ubuntu-base", cpus = 2, memory = 2048 }
  
  # Database cluster
  "db-primary"   = { template_name = "ubuntu-base", cpus = 4, memory = 8192 }
  "db-secondary" = { template_name = "ubuntu-base", cpus = 4, memory = 8192 }
  
  # Application servers
  "app-01" = { template_name = "ubuntu-base", cpus = 2, memory = 4096 }
  "app-02" = { template_name = "ubuntu-base", cpus = 2, memory = 4096 }
  
  # Support services
  "cache"    = { template_name = "ubuntu-base", cpus = 2, memory = 4096 }
  "monitor"  = { template_name = "ubuntu-base", cpus = 1, memory = 2048 }
}
```

This creates 9 VMs in minutes, all from a single template!

## Troubleshooting

### Template Issues

**Template won't create:**
- Ensure VM is stopped: `prlctl stop <vm-name>`
- Check disk space: `df -h ~/Parallels`
- Verify permissions on VM files

**Clone fails:**
- Check template exists: `prlctl list -t`
- For linked clones, ensure parent hasn't moved
- Try full clone if linked fails

**Cloud-init not working:**
- Verify cloud-init was cleaned in template
- Check cloud-init ISO is attached
- Review logs: `cloud-init status --long`

### Performance Issues

**Slow cloning:**
- Use SSDs for VM storage
- Enable linked clones
- Check host resource usage
- Close unnecessary applications

**High disk usage:**
- Use linked clones for development
- Regularly clean old templates
- Compress PVM bundles for storage

### Network Issues

**No IP address:**
- Wait for cloud-init to complete
- Check Parallels network settings
- Verify DHCP is enabled
- Try manual network restart

## Automation Examples

### Automated Template Updates
```bash
#!/bin/bash
# Using manage-templates.sh update command

TEMPLATE="ubuntu-base-template"

# Clone template
prlctl clone "$TEMPLATE" --name "$UPDATE_VM"

# Start and update
prlctl start "$UPDATE_VM"
sleep 30

# Get IP and update
IP=$(prlctl list -f | grep "$UPDATE_VM" | awk '{print $3}')
ssh ubuntu@"$IP" "sudo apt update && sudo apt upgrade -y"

# Shutdown and prepare
prlctl stop "$UPDATE_VM"
./scripts/prepare-vm-template.sh "$UPDATE_VM"

# Create new version
DATE=$(date +%Y%m%d)
./scripts/create-parallels-template.sh "$UPDATE_VM" template
prlctl set "${UPDATE_VM}-template" --name "${TEMPLATE}-${DATE}"

# Cleanup
prlctl delete "$UPDATE_VM"
```

### Bulk VM Deployment
```bash
#!/bin/bash
# Deploy multiple VMs from template

TEMPLATE="ubuntu-base-template"
COUNT=10

for i in $(seq 1 $COUNT); do
  prlctl clone "$TEMPLATE" \
    --name "vm-${i}" \
    --linked \
    --changesid
done
```

## Clean Up

To remove all VMs:
```bash
tofu destroy
```

To remove a template:
```bash
./scripts/manage-templates.sh delete ubuntu-base-template
```

## Next Steps

- Review [Deployment Methods](deployment-methods.md) for comprehensive options
- Check [Template Maintenance](TEMPLATE-MAINTENANCE.md) for update procedures
- See [Troubleshooting](troubleshooting.md) for detailed problem resolution
- Explore [Cloud-Init Examples](../opentofu/cloud-init-examples/) for configurations