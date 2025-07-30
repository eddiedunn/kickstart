# OpenTofu Template-Based VM Deployment Guide

This guide covers deploying VMs from templates, PVM bundles, and snapshots using OpenTofu with Parallels Desktop.

## Overview

The enhanced OpenTofu configuration now supports three VM deployment methods:

1. **ISO-based deployment** (original method) - Fresh installations from ISO files
2. **Template-based deployment** (new) - Clone from pre-configured VM templates
3. **Hybrid deployment** - Mix of both methods in the same infrastructure

## Template Deployment Methods

### 1. Linked Clones from Templates

**Advantages:**
- Fastest deployment (seconds vs minutes)
- Minimal disk usage (only differences stored)
- Shared base image reduces storage

**Best for:**
- Development environments
- Testing scenarios
- Temporary VMs

**Configuration:**
```hcl
vm_template_definitions = {
  "dev-vm" = {
    name         = "dev-environment"
    source_type  = "template"
    source_name  = "ubuntu-22.04-base"
    linked_clone = true  # Enable linked clone
    cloud_init   = true
  }
}
```

### 2. PVM Bundle Deployment

**Advantages:**
- Portable VM packages
- Version control friendly
- Easy distribution

**Best for:**
- Pre-configured applications
- Standardized environments
- VM archival

**Configuration:**
```hcl
vm_template_definitions = {
  "app-server" = {
    name        = "application-server"
    source_type = "pvm"
    source_name = "app-server-v2.1.pvm"  # or full path
    cloud_init  = true
  }
}
```

### 3. Snapshot-Based Deployment

**Advantages:**
- Point-in-time recovery
- Multiple restore points
- Preserves exact state

**Best for:**
- Complex configurations
- Stateful applications
- Testing rollbacks

**Configuration:**
```hcl
vm_template_definitions = {
  "test-restore" = {
    name        = "test-environment"
    source_type = "snapshot"
    source_name = "clean-state"      # Snapshot name
    source_vm   = "ubuntu-dev-base"  # VM containing snapshot
    cloud_init  = false  # Usually skip for snapshots
  }
}
```

## Creating VM Templates

### Step 1: Install Base VM

```bash
# Deploy a fresh VM using ISO method
tofu apply -var-file=base-vm.tfvars

# Or manually create and configure a VM
```

### Step 2: Prepare VM for Template

```bash
# Use the preparation script
./scripts/manage-templates.sh prepare-base --name ubuntu-base

# This will:
# - Clean package caches
# - Clear cloud-init data
# - Remove SSH host keys
# - Clear machine IDs
# - Truncate logs
```

### Step 3: Convert to Template

```bash
# Option 1: Convert to Parallels template
./scripts/manage-templates.sh create-template --name ubuntu-base

# Option 2: Export as PVM bundle
./scripts/manage-templates.sh export-pvm --name ubuntu-base --file ubuntu-base-v1.0.pvm

# Option 3: Take a snapshot
./scripts/manage-templates.sh take-snapshot --name ubuntu-base --snapshot initial-setup
```

## Cloud-Init Integration

### Basic Cloud-Init Configuration

Cloud-init runs on first boot to customize the cloned VM:

```yaml
#cloud-config
hostname: web-server
manage_etc_hosts: true

users:
  - default
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...

packages:
  - nginx
  - git

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
```

### Advanced Customization

```hcl
vm_template_definitions = {
  "custom-vm" = {
    name        = "custom-server"
    source_type = "template"
    source_name = "ubuntu-base"
    
    # Hardware overrides
    cpus   = 4
    memory = 8192
    
    # Cloud-init configuration
    cloud_init = true
    cloud_init_files = {
      user_data    = "./cloud-init/custom-user-data.yaml"
      meta_data    = "./cloud-init/custom-meta-data.yaml"
      network_data = "./cloud-init/custom-network-data.yaml"
    }
    
    # Direct customizations
    customize = {
      hostname    = "custom-server"
      ip_address  = "192.168.1.100"
      gateway     = "192.168.1.1"
      dns_servers = ["8.8.8.8", "8.8.4.4"]
      ssh_keys    = [
        "ssh-rsa AAAAB3...",
        "ssh-ed25519 AAAAC3..."
      ]
    }
  }
}
```

## Multi-VM Deployment Example

Deploy a complete application stack:

```hcl
vm_template_definitions = {
  # Load balancer
  "lb" = {
    name         = "load-balancer"
    source_type  = "template"
    source_name  = "ubuntu-nginx"
    cpus         = 2
    memory       = 2048
    linked_clone = true
    cloud_init_files = {
      user_data = "./cloud-init/lb-config.yaml"
    }
  }
  
  # Web servers
  "web-1" = {
    name         = "web-server-1"
    source_type  = "template"
    source_name  = "ubuntu-apache"
    cpus         = 2
    memory       = 4096
    linked_clone = true
    start_after  = ["lb"]  # Start after load balancer
  }
  
  "web-2" = {
    name         = "web-server-2"
    source_type  = "template"
    source_name  = "ubuntu-apache"
    cpus         = 2
    memory       = 4096
    linked_clone = true
    start_after  = ["lb"]
  }
  
  # Database
  "db" = {
    name        = "database"
    source_type = "pvm"
    source_name = "postgresql-14-configured.pvm"
    cpus        = 4
    memory      = 8192
    cloud_init  = false  # Already configured in PVM
  }
  
  # Cache
  "cache" = {
    name         = "redis-cache"
    source_type  = "snapshot"
    source_name  = "redis-configured"
    source_vm    = "redis-base"
    start_after  = ["db"]
  }
}
```

## Lifecycle Management

### Creating Infrastructure

```bash
# Initialize OpenTofu
tofu init

# Plan deployment
tofu plan -var-file=terraform.tfvars

# Apply configuration
tofu apply -var-file=terraform.tfvars
```

### Updating VMs

#### Hardware Changes
```bash
# Modify tfvars file to change CPU/memory
# Then apply changes
tofu apply -var-file=terraform.tfvars
```

#### Re-run Cloud-Init
```bash
# Modify cloud-init files
# Taint the cloud-init resource to force recreation
tofu taint 'module.template_vms["web-1"].null_resource.cloud_init_iso[0]'
tofu apply
```

### Destroying Resources

```bash
# Destroy all VMs
tofu destroy

# Destroy specific VMs
tofu destroy -target='module.template_vms["web-1"]'
```

## Best Practices

### 1. Template Maintenance

- **Version templates**: Include version in template names (e.g., `ubuntu-22.04-v1.2`)
- **Document changes**: Maintain a changelog for each template
- **Regular updates**: Schedule monthly template updates
- **Test templates**: Validate templates before production use

### 2. Security Considerations

- **Remove sensitive data**: Clear all credentials before creating templates
- **Regenerate keys**: Ensure SSH host keys regenerate on clone
- **Update regularly**: Keep base images patched
- **Audit access**: Control who can access templates

### 3. Performance Optimization

- **Use linked clones**: For development/testing environments
- **Optimize base image**: Remove unnecessary packages
- **Pre-install tools**: Include common utilities in templates
- **Configure resources**: Set appropriate CPU/memory limits

### 4. Cloud-Init Best Practices

- **Idempotent scripts**: Ensure cloud-init can run multiple times
- **Error handling**: Add proper error checking in runcmd
- **Logging**: Log cloud-init actions for debugging
- **Timeout handling**: Set appropriate timeouts for long operations

### 5. Naming Conventions

```
Templates: <os>-<version>-<role>-<version>
  Example: ubuntu-22.04-web-v1.0

PVM Bundles: <name>-<version>-<date>.pvm
  Example: webapp-v2.1-20240115.pvm

Snapshots: <purpose>-<date>-<version>
  Example: pre-upgrade-20240115-v1
```

## Troubleshooting

### VM Creation Fails

```bash
# Check Parallels Desktop status
prlctl list -a

# Check template exists
prlctl list -t

# Verify PVM bundle path
ls -la ~/Parallels/Bundles/

# Check logs
tail -f /var/log/parallels.log
```

### Cloud-Init Issues

```bash
# Check cloud-init status
prlctl exec <vm-name> "cloud-init status"

# View cloud-init logs
prlctl exec <vm-name> "sudo cat /var/log/cloud-init.log"

# Validate cloud-config
cloud-init devel schema --config-file <user-data.yaml>
```

### Network Problems

```bash
# Check VM network settings
prlctl list -i <vm-name>

# Verify IP assignment
prlctl exec <vm-name> "ip addr show"

# Test connectivity
prlctl exec <vm-name> "ping -c 3 8.8.8.8"
```

## Advanced Topics

### Custom Module Development

Create specialized modules for specific use cases:

```hcl
module "kubernetes_cluster" {
  source = "./modules/k8s-cluster"
  
  master_template = "ubuntu-k8s-master"
  worker_template = "ubuntu-k8s-worker"
  worker_count    = 3
  
  network_cidr = "10.0.0.0/16"
}
```

### Integration with CI/CD

```yaml
# GitLab CI example
deploy-test-env:
  script:
    - tofu init
    - tofu apply -auto-approve -var-file=test.tfvars
  environment:
    name: test
    on_stop: destroy-test-env

destroy-test-env:
  script:
    - tofu destroy -auto-approve -var-file=test.tfvars
  when: manual
```

### State Management

```bash
# Use remote state backend
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "parallels/vms.tfstate"
    region = "us-east-1"
  }
}
```

## Conclusion

Template-based deployment with OpenTofu and Parallels Desktop provides:

- **Speed**: Deploy VMs in seconds instead of minutes
- **Consistency**: Ensure identical base configurations
- **Flexibility**: Mix deployment methods as needed
- **Automation**: Full infrastructure as code support

For questions or issues, refer to:
- [Parallels Desktop Documentation](https://www.parallels.com/products/desktop/resources/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)