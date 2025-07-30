# Template-Based Deployment Quick Start

Deploy multiple Ubuntu VMs in seconds using pre-configured templates!

## Prerequisites

- Parallels Desktop with existing Ubuntu template
- OpenTofu/Terraform installed
- SSH keys configured

## 1. Quick Deploy (< 1 minute per VM)

```bash
cd opentofu

# Use example configuration
cp terraform.tfvars.template-example terraform.tfvars
# Edit to specify your template name

# Deploy
tofu init
tofu apply
```

## 2. Configuration Examples

### Simple Single VM
```hcl
vm_template_definitions = {
  "dev" = {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true  # Fast & space-efficient
  }
}
```

### Multiple VMs with Customization
```hcl
vm_template_definitions = {
  "web" = {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cpus         = 2
    memory       = 4096
    cloud_init   = true
    cloud_init_files = {
      user_data = "./cloud-init/web.yaml"
    }
  }
  "db" = {
    source_type  = "template"
    source_name  = "ubuntu-base-template"
    linked_clone = true
    cpus         = 4
    memory       = 8192
    cloud_init   = true
    cloud_init_files = {
      user_data = "./cloud-init/database.yaml"
    }
  }
}
```

## 3. Access Your VMs

```bash
# Check status and get IPs
./scripts/status.sh

# SSH to VMs
ssh ubuntu@<ip-address>
```

## Creating Your First Template

Don't have a template yet? Create one:

```bash
# 1. Deploy base VM from ISO
./scripts/build-autoinstall-iso.sh ubuntu.iso
cd opentofu && tofu apply

# 2. Customize the VM (install software, configure settings)
ssh ubuntu@<vm-ip>
# ... make your changes ...

# 3. Convert to template
./scripts/prepare-vm-template.sh ubuntu-base
./scripts/create-parallels-template.sh ubuntu-base template
```

## Template Types

- **Linked Clone** (Recommended): ~10% disk usage, < 1 min deployment
- **Full Clone**: Independent copy, 2-3 min deployment
- **PVM Bundle**: Portable template file, 3-5 min deployment

## Tips

- **Use linked clones** for development (90% space savings)
- **Keep templates updated** monthly for security
- **Use cloud-init** for VM-specific configuration
- **Version your templates** (e.g., ubuntu-base-v1.2)

## Common Issues

**Template not found?**
```bash
prlctl list -t  # List available templates
```

**Slow cloning?**
- Use linked clones: `linked_clone = true`
- Check disk space: `df -h ~/Parallels`

**Cloud-init not working?**
- Ensure template was prepared with `prepare-vm-template.sh`
- Check logs: `cloud-init status --long`

## Next Steps

- [Create custom templates](TEMPLATE-MAINTENANCE.md)
- [Advanced deployment options](deployment-methods.md)
- [Troubleshooting guide](troubleshooting.md)