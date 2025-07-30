# Parallels VM Templating Guide for OpenTofu

## Overview

This guide explains how to create reusable VM templates from existing Parallels Desktop VMs for use with OpenTofu infrastructure automation.

## Template Creation Methods

### Method 1: Linked Clone Template (Recommended)

**Pros:**
- Fast cloning (uses copy-on-write)
- Minimal disk space usage
- Native Parallels template support
- Best performance for local deployments

**Cons:**
- Not portable between hosts
- Requires original VM to remain intact

**Command:**
```bash
prlctl clone {vm-uuid} --name "template-name" --template
```

### Method 2: PVM Bundle Export

**Pros:**
- Fully portable between hosts
- Self-contained package
- Can be versioned and stored in artifact repositories
- Works across different Parallels installations

**Cons:**
- Larger file size
- Slower to deploy
- Requires import step

**Command:**
```bash
prlctl export {vm-uuid} -o template.pvm
```

### Method 3: Snapshot-Based Cloning

**Pros:**
- Allows multiple template versions
- Easy rollback capability
- Good for iterative development

**Cons:**
- Not a true template
- Snapshot chain can impact performance
- Not portable

**Command:**
```bash
prlctl snapshot {vm-uuid} --name "base-template"
```

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

## OpenTofu Integration

### Provider Configuration

```hcl
terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.3.0"
    }
  }
}

provider "parallels-desktop" {
  # Provider configuration
}
```

### Deployment Examples

#### From Template UUID
```hcl
resource "parallels-desktop_vm" "vm" {
  name = "my-ubuntu-vm"
  
  clone {
    source_uuid = "template-uuid-here"
  }
  
  config {
    cpu_count   = 2
    memory_size = 2048
  }
}
```

#### From PVM Bundle
```hcl
resource "parallels-desktop_vm" "vm" {
  name = "my-ubuntu-vm"
  
  pvm_bundle {
    path = "./templates/ubuntu-template.pvm"
  }
}
```

## Best Practices

### 1. Naming Conventions
- Use descriptive names: `ubuntu-22.04-base-YYYYMMDD`
- Include OS version and date
- Add purpose suffix: `-web`, `-db`, `-dev`

### 2. Version Control
- Store template metadata in Git
- Track checksums for PVM bundles
- Document template contents

### 3. Security Considerations
- Remove all credentials before templating
- Disable password authentication
- Use cloud-init for secure provisioning
- Rotate SSH keys on deployment

### 4. Storage Management
- Store PVM bundles in artifact repositories
- Use compression for long-term storage
- Implement retention policies
- Consider using Parallels shared storage for teams

### 5. Testing
- Always test template deployment before production use
- Verify cloud-init runs correctly
- Check network connectivity
- Validate all services start properly

## Troubleshooting

### Common Issues

1. **Template Won't Clone**
   - Ensure VM is stopped
   - Check disk space
   - Verify Parallels permissions

2. **Network Issues After Cloning**
   - Machine ID may be duplicated
   - Check if MAC addresses need regeneration
   - Verify cloud-init network config

3. **Cloud-Init Not Running**
   - Ensure cloud-init is not disabled
   - Check for valid metadata source
   - Verify cloud-init package is installed

### Diagnostic Commands

```bash
# Check template status
prlctl list --template

# Verify VM state
prlctl status {vm-uuid}

# Test clone operation
prlctl clone {template-uuid} --name test-clone

# Check cloud-init status (inside VM)
cloud-init status --long
```

## Automation Workflow

1. **Build Phase**
   - Deploy base VM with Kickstart
   - Apply security hardening
   - Install required packages

2. **Template Phase**
   - Run generalization script
   - Create template/export
   - Generate metadata

3. **Deploy Phase**
   - Clone from template
   - Apply cloud-init config
   - Run post-deployment scripts

4. **Validate Phase**
   - Test connectivity
   - Verify services
   - Run smoke tests