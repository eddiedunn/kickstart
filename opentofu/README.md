# OpenTofu/Terraform Configuration for Ubuntu VM Deployment

This directory contains Infrastructure as Code (IaC) configurations for deploying Ubuntu VMs on Parallels Desktop using OpenTofu (or Terraform).

## Overview

The configuration supports two primary deployment methods:

1. **ISO-based Deployment** (`main.tf`) - Fresh installations from custom Ubuntu ISOs
2. **Template-based Deployment** (`main-templates.tf`) - Fast cloning from VM templates

Both methods support cloud-init for post-deployment configuration.

## Directory Structure

```
opentofu/
├── main.tf                  # ISO-based VM deployments
├── main-templates.tf        # Template-based VM deployments
├── variables.tf             # Input variable definitions
├── outputs.tf               # Output definitions
├── terraform.tfvars.example # Example configuration (ISO)
├── terraform.tfvars.template-example # Example configuration (templates)
├── modules/
│   ├── parallels-vm/       # Module for ISO-based VMs
│   └── vm-template/        # Module for template-based VMs
└── cloud-init-examples/    # Sample cloud-init configurations
```

## Prerequisites

- **OpenTofu** (preferred) or **Terraform** >= 1.0
- **Parallels Desktop** Pro or Business Edition
- **Parallels Provider** for Terraform
- Ubuntu ISO (for ISO-based deployment)
- VM template (for template-based deployment)

## Quick Start

### ISO-based Deployment

1. Copy the example configuration:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` to specify your ISO path and VM settings:
   ```hcl
   vm_definitions = {
     "web-server" = {
       name      = "ubuntu-web"
       iso_path  = "../output/ubuntu-autoinstall.iso"
       cpus      = 2
       memory    = 4096
       disk_size = 30
     }
   }
   ```

3. Initialize and deploy:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

### Template-based Deployment

1. Ensure you have a VM template (see scripts/manage-templates.sh)

2. Copy the template example:
   ```bash
   cp terraform.tfvars.template-example terraform.tfvars
   ```

3. Edit `terraform.tfvars`:
   ```hcl
   vm_template_definitions = {
     "app-server" = {
       source_type  = "template"
       source_name  = "ubuntu-base-template"
       linked_clone = true
       cpus         = 2
       memory       = 2048
     }
   }
   ```

4. Deploy:
   ```bash
   tofu init
   tofu apply
   ```

## Configuration Options

### Common Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `headless` | Run VMs without GUI | `false` |
| `enable_nested_virt` | Enable nested virtualization | `false` |
| `ssh_public_key_path` | Path to SSH public key | Auto-detected |

### VM Definition Properties

#### ISO-based VMs
- `name` - VM name in Parallels
- `iso_path` - Path to Ubuntu ISO
- `cpus` - Number of CPU cores
- `memory` - RAM in MB
- `disk_size` - Disk size in GB
- `network` - Network type ("shared", "host-only", "bridged")

#### Template-based VMs
- `source_type` - Must be "template"
- `source_name` - Name of the template
- `linked_clone` - Use linked clones (saves space)
- `cloud_init` - Enable cloud-init configuration
- `cloud_init_files` - Paths to user-data/meta-data files

## Cloud-Init Integration

Both deployment methods support cloud-init for VM customization:

1. Create a cloud-init user-data file:
   ```yaml
   #cloud-config
   hostname: my-server
   packages:
     - nginx
     - docker.io
   runcmd:
     - systemctl enable nginx
   ```

2. Reference it in your VM definition:
   ```hcl
   cloud_init_files = {
     user_data = "./cloud-init/my-server.yaml"
   }
   ```

## Module Usage

### parallels-vm Module

For ISO-based deployments:

```hcl
module "ubuntu_vm" {
  source = "./modules/parallels-vm"
  
  vm_name     = "ubuntu-server"
  iso_path    = "/path/to/ubuntu.iso"
  cpus        = 4
  memory      = 8192
  disk_size   = 50
}
```

### vm-template Module

For template-based deployments:

```hcl
module "app_server" {
  source = "./modules/vm-template"
  
  vm_name      = "app-01"
  template_name = "ubuntu-base"
  linked_clone = true
  
  cloud_init_user_data = file("./cloud-init/app-server.yaml")
}
```

## Common Operations

### Deploy specific VMs only
```bash
tofu apply -target='module.template_vms["web"]'
```

### Destroy specific VMs
```bash
tofu destroy -target='module.template_vms["web"]'
```

### List deployed resources
```bash
tofu state list
```

### Show VM details
```bash
tofu show
```

## Outputs

The configuration provides these outputs:

- `vm_info` - Details about ISO-deployed VMs
- `template_vm_info` - Details about template-deployed VMs

Access outputs:
```bash
tofu output vm_info
tofu output -json template_vm_info
```

## Best Practices

1. **Use Templates for Production** - Faster deployment and consistent base images
2. **Enable Linked Clones** - Saves significant disk space
3. **Version Control tfvars** - Track your infrastructure configurations
4. **Use Cloud-Init** - Automate post-deployment configuration
5. **Regular Template Updates** - Keep base images patched

## Troubleshooting

### Provider Issues
```bash
# Ensure provider is installed
tofu init -upgrade

# Check provider version
tofu version
```

### VM Creation Fails
- Check Parallels Desktop is running
- Verify ISO/template paths are correct
- Ensure sufficient disk space
- Review Parallels logs: `~/Library/Logs/parallels.log`

### State Issues
```bash
# Refresh state
tofu refresh

# Import existing VMs
tofu import 'module.vm["web"]' <vm-uuid>
```

## Security Considerations

1. **SSH Keys** - Never commit private keys
2. **Passwords** - Use hashed passwords in cloud-init
3. **State Files** - Contains sensitive data, don't commit
4. **Network** - Consider using host-only networks for isolation

## Advanced Usage

### Multi-environment Deployments
```bash
# Development
tofu workspace new dev
tofu apply -var-file=dev.tfvars

# Production
tofu workspace new prod
tofu apply -var-file=prod.tfvars
```

### Remote State Storage
Configure backend for team collaboration:
```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "parallels-vms/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Related Documentation

- [Parallels Provider Documentation](https://registry.terraform.io/providers/parallels/parallels-desktop/latest/docs)
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)