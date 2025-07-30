# Scripts Directory

This directory contains automation scripts for managing Ubuntu VMs on Parallels Desktop. The scripts are designed to work together as a complete VM lifecycle management toolkit.

## Script Overview

### Core VM Management

#### `build-autoinstall-iso.sh`
Creates custom Ubuntu Server ISOs with embedded autoinstall configuration for unattended installation.

**Key Features:**
- Embeds autoinstall configuration into Ubuntu ISO
- Automatically includes SSH public keys from `~/.ssh/*.pub`
- Configures DHCP networking and cloud-init
- Creates timestamped ISOs in `output/` directory

**Usage:**
```bash
./build-autoinstall-iso.sh ~/Downloads/ubuntu-22.04.5-live-server-arm64.iso
```

#### `deploy-vm.sh`
Quick VM deployment from autoinstall ISO without using IaC tools.

**Key Features:**
- Creates and starts VM with predefined specs
- Handles both ARM64 and x86_64 architectures
- Configures 2 CPUs, 4GB RAM, 20GB disk
- Uses Parallels Shared (NAT) networking

**Usage:**
```bash
./deploy-vm.sh output/ubuntu-autoinstall.iso my-vm
```

### Template Management

#### `manage-templates.sh`
Comprehensive template management system - your main tool for template operations.

**Commands:**
- `list` - Show all templates
- `create <vm>` - Create template from VM (includes preparation)
- `clone <template>` - Deploy VM from template
- `update <template>` - Update template with OS patches
- `export <template>` - Create portable PVM bundle
- `import <pvm>` - Import PVM as template
- `delete <template>` - Remove template

**Usage:**
```bash
# Create template from VM
./manage-templates.sh create ubuntu-base

# Deploy linked clone
./manage-templates.sh clone ubuntu-base-template --name web-01 --linked

# Update template
./manage-templates.sh update ubuntu-base-template
```

#### `prepare-vm-template.sh`
Prepares VM for conversion to template by removing machine-specific data.

**What it does:**
- Cleans package caches and logs
- Removes SSH host keys
- Clears machine IDs
- Resets cloud-init state
- Zeros free disk space

**Usage:**
```bash
./prepare-vm-template.sh my-vm
```

#### `create-parallels-template.sh`
Creates templates in various formats from prepared VMs.

**Modes:**
- `template` - Linked-clone template (default)
- `export` - Portable PVM bundle
- `snapshot` - VM snapshot
- `all` - All formats

**Usage:**
```bash
# Create linked-clone template
./create-parallels-template.sh ubuntu-base

# Export as PVM
./create-parallels-template.sh ubuntu-base export

# Create all formats
./create-parallels-template.sh ubuntu-base all
```

### Validation and Monitoring

#### `validate-config.sh`
Validates autoinstall and cloud-init YAML configurations.

**Checks:**
- YAML syntax validation
- Cloud-init schema compliance
- Security best practices
- Required fields presence

**Usage:**
```bash
# Validate all configs
./validate-config.sh

# Validate specific file
./validate-config.sh autoinstall/user-data
```

#### `status.sh`
Real-time VM status monitoring with SSH connectivity checks.

**Features:**
- Color-coded VM states
- IP address detection
- SSH port testing
- Watch mode for continuous monitoring
- Verbose mode for detailed info

**Usage:**
```bash
# Single status check
./status.sh

# Continuous monitoring
./status.sh --watch

# Detailed view with slow refresh
./status.sh --verbose --watch --interval 10
```

### Maintenance

#### `cleanup.sh`
Safely removes VMs, ISOs, and IaC state files.

**Options:**
- `--isos` - Also remove ISO files
- `--all` - Remove everything including Terraform state
- `--force` - Skip confirmation prompts

**Usage:**
```bash
# Clean VMs only
./cleanup.sh

# Clean VMs and ISOs
./cleanup.sh --isos

# Full cleanup (use with caution)
./cleanup.sh --all --force
```

## Typical Workflows

### 1. Create Custom VM from ISO

```bash
# Build custom ISO
./build-autoinstall-iso.sh ubuntu-22.04.5-live-server-arm64.iso

# Deploy VM
./deploy-vm.sh output/ubuntu-minimal-autoinstall-*.iso test-vm

# Check status
./status.sh --watch

# Create template when ready
./manage-templates.sh create test-vm
```

### 2. Template-Based Deployment

```bash
# Use existing template
./manage-templates.sh list

# Clone template
./manage-templates.sh clone ubuntu-base-template --name app-01 --linked

# Deploy multiple VMs
for i in {1..3}; do
  ./manage-templates.sh clone ubuntu-base-template --name "web-0$i" --linked
done

# Monitor deployments
./status.sh --watch
```

### 3. Template Maintenance

```bash
# Update template with patches
./manage-templates.sh update ubuntu-base-template

# Export for backup
./manage-templates.sh export ubuntu-base-template

# Import on another system
./manage-templates.sh import templates/ubuntu-base-template-*.pvm
```

### 4. Development Cleanup

```bash
# Check what will be cleaned
./status.sh

# Clean test VMs
./cleanup.sh

# Full reset
./cleanup.sh --all
```

## Best Practices

1. **Always validate configurations** before building ISOs:
   ```bash
   ./validate-config.sh autoinstall/user-data
   ```

2. **Use templates for production** deployments:
   - Faster deployment (10-30 seconds vs 5-10 minutes)
   - Consistent base configuration
   - Space efficient with linked clones

3. **Keep templates updated**:
   ```bash
   # Monthly update routine
   ./manage-templates.sh update ubuntu-base-template
   ./manage-templates.sh export ubuntu-base-template
   ```

4. **Monitor deployments** to catch issues early:
   ```bash
   ./status.sh --watch --verbose
   ```

5. **Clean up regularly** to save disk space:
   ```bash
   ./cleanup.sh --isos
   ```

## Environment Variables

- `TEMPLATES_DIR` - Template metadata storage (default: `~/Parallels/Templates`)
- `EXPORT_DIR` - PVM export location (default: `./templates`)

## Prerequisites

- **Parallels Desktop Pro/Business** - Required for advanced features
- **OpenTofu or Terraform** - For IaC deployments
- **xorriso** - For ISO manipulation (`brew install xorriso`)
- **jq** - For JSON processing (`brew install jq`)
- **cloud-init** - For config validation (`apt-get install cloud-init`)
- **yq** - For YAML parsing (`brew install yq`)

## Troubleshooting

### Common Issues

1. **ISO creation fails**
   - Check xorriso is installed
   - Verify source ISO path
   - Ensure 5GB free disk space

2. **VM won't start**
   - Check Parallels Desktop is running
   - Verify sufficient RAM available
   - Review ISO architecture matches host

3. **Template creation fails**
   - Ensure VM is prepared first
   - Check VM is stopped
   - Verify disk space for chosen format

4. **SSH connection fails**
   - Wait for cloud-init to complete
   - Check VM has IP address
   - Verify SSH keys are configured

### Debug Commands

```bash
# Check Parallels logs
tail -f ~/Library/Logs/parallels.log

# Verify VM state
prlctl list -i <vm-name>

# Check cloud-init status
prlctl exec <vm-name> "cloud-init status"

# View cloud-init logs
prlctl exec <vm-name> "sudo journalctl -u cloud-init"
```

## Script Dependencies

```
build-autoinstall-iso.sh
    └── creates ISO for →
        deploy-vm.sh
            └── creates VM for →
                prepare-vm-template.sh
                    └── prepares VM for →
                        create-parallels-template.sh / manage-templates.sh

validate-config.sh → validates configs for → build-autoinstall-iso.sh
status.sh → monitors → all VMs
cleanup.sh → removes → all VMs and artifacts
```

## Security Considerations

1. **SSH Keys**: Never commit private keys. Scripts only use public keys.
2. **Passwords**: Default password is for initial access only. Use SSH keys.
3. **Templates**: Remove sensitive data before creating templates.
4. **Validation**: Always validate configurations before deployment.

## Contributing

When adding new scripts:
1. Follow the existing header documentation format
2. Include usage examples
3. Document all parameters and options
4. Add error handling and validation
5. Update this README

## Related Documentation

- [VM Deployment Methods](../docs/VM-DEPLOYMENT-METHODS.md)
- [Template Guide](../docs/VM-TEMPLATE-GUIDE.md)
- [OpenTofu Configuration](../opentofu/README.md)
- [Troubleshooting Guide](../docs/troubleshooting.md)