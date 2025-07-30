# OpenTofu VM Template Deployment

This directory now supports deploying VMs from templates, PVM bundles, and snapshots in addition to ISO-based installations.

## Quick Start

### 1. Create a Base Template

First, create a base VM template from an existing VM:

```bash
# Prepare an existing VM to be a template
../scripts/manage-templates.sh prepare-base --name ubuntu-fresh

# Convert to template
../scripts/manage-templates.sh create-template --name ubuntu-fresh
```

### 2. Configure Template Deployment

Copy the template example configuration:

```bash
cp terraform.tfvars.template-example terraform.tfvars
```

Edit `terraform.tfvars` to define your template-based VMs:

```hcl
vm_template_definitions = {
  "web" = {
    name         = "web-server"
    source_type  = "template"
    source_name  = "ubuntu-fresh"  # Your template name
    cpus         = 2
    memory       = 4096
    linked_clone = true
    cloud_init   = true
  }
}
```

### 3. Deploy VMs

```bash
# Initialize OpenTofu
tofu init

# Deploy VMs from templates
tofu apply
```

## File Structure

```
opentofu/
├── main.tf                    # Original ISO-based deployment
├── main-templates.tf          # Template-based deployment
├── variables.tf               # Original variables
├── variables-templates.tf     # Template-specific variables
├── outputs.tf                 # Original outputs
├── outputs-templates.tf       # Template-specific outputs
├── modules/
│   └── vm-template/          # Module for template deployments
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── cloud-init-examples/       # Example cloud-init configurations
│   ├── web-server-user-data.yaml
│   └── database-user-data.yaml
├── terraform.tfvars.example   # ISO deployment example
└── terraform.tfvars.template-example  # Template deployment example
```

## Deployment Methods

### Method 1: Linked Clone from Template (Fastest)

```hcl
source_type  = "template"
source_name  = "ubuntu-base"
linked_clone = true
```

### Method 2: PVM Bundle Import

```hcl
source_type = "pvm"
source_name = "ubuntu-configured.pvm"  # or full path
```

### Method 3: Snapshot Restore

```hcl
source_type = "snapshot"
source_name = "clean-install"    # Snapshot name
source_vm   = "ubuntu-template"  # VM containing snapshot
```

## Cloud-Init Customization

### Basic (Auto-Generated)

```hcl
cloud_init = true
customize = {
  hostname = "my-server"
  ssh_keys = ["ssh-rsa AAAA..."]
}
```

### Advanced (Custom Files)

```hcl
cloud_init = true
cloud_init_files = {
  user_data = "./cloud-init-examples/web-server-user-data.yaml"
  meta_data = "./my-meta-data.yaml"
}
```

## Mixed Deployments

You can deploy both ISO-based and template-based VMs simultaneously:

```hcl
# ISO-based VMs
vm_definitions = {
  "fresh" = {
    name     = "ubuntu-fresh-install"
    iso_path = "../output/ubuntu-autoinstall.iso"
    # ...
  }
}

# Template-based VMs
vm_template_definitions = {
  "clone" = {
    name        = "ubuntu-from-template"
    source_type = "template"
    source_name = "ubuntu-base"
    # ...
  }
}
```

## Commands Reference

### Template Management

```bash
# List all templates
../scripts/manage-templates.sh list-templates

# Create template from VM
../scripts/manage-templates.sh create-template --name <vm-name>

# Export VM as PVM bundle
../scripts/manage-templates.sh export-pvm --name <vm-name> --file <output.pvm>

# Take VM snapshot
../scripts/manage-templates.sh take-snapshot --name <vm-name> --snapshot <snapshot-name>
```

### OpenTofu Commands

```bash
# Initialize
tofu init

# Plan deployment
tofu plan

# Apply configuration
tofu apply

# Destroy specific VMs
tofu destroy -target='module.template_vms["web"]'

# Destroy all
tofu destroy
```

### Useful Parallels Commands

```bash
# List all VMs
prlctl list -a

# List templates only
prlctl list -t

# Get VM info
prlctl list -i <vm-name>

# Clone manually
prlctl clone <template> --name <new-vm> --linked

# Check cloud-init status
prlctl exec <vm-name> "cloud-init status"
```

## Best Practices

1. **Template Hygiene**: Always run `prepare-base` before creating templates
2. **Version Control**: Include version numbers in template names
3. **Resource Limits**: Set appropriate CPU/memory limits
4. **Security**: Regenerate SSH keys and machine IDs on clone
5. **Documentation**: Document template contents and requirements

## Troubleshooting

### VM Creation Fails
- Verify template exists: `prlctl list -t`
- Check template name spelling in tfvars
- Ensure sufficient disk space for clones

### Cloud-Init Not Running
- Verify cloud-init is installed in template
- Check cloud-init ISO creation: `ls cloud-init-isos/`
- Review logs: `prlctl exec <vm> "sudo journalctl -u cloud-init"`

### Network Issues
- Check network type matches template configuration
- Verify DHCP availability for `shared` network
- Use static IPs in `customize` block if needed

## Next Steps

1. Review the [full documentation](../docs/opentofu-template-deployment.md)
2. Create your first template using the preparation script
3. Deploy a multi-VM environment using templates
4. Customize cloud-init for your specific needs

For more examples and advanced configurations, see the documentation in the `docs/` directory.