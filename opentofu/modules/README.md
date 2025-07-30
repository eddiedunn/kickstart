# OpenTofu/Terraform Modules

This directory contains reusable modules for deploying Ubuntu VMs on Parallels Desktop. Each module provides a different deployment method with consistent interfaces.

## Available Modules

### parallels-vm

Universal VM deployment module supporting multiple source types:
- **ISO-based**: Fresh installation from Ubuntu autoinstall ISO
- **Template-based**: Clone from existing Parallels template
- **PVM import**: Import from exported PVM bundle

### vm-template

Specialized module for template-based deployments with cloud-init support. Provides simplified interface for common template operations.

## Module Comparison

| Feature | parallels-vm | vm-template |
|---------|--------------|-------------|
| ISO deployment | ✅ | ❌ |
| Template cloning | ✅ | ✅ |
| PVM import | ✅ | ❌ |
| Cloud-init | ✅ | ✅ |
| Linked clones | ✅ | ✅ |
| Multi-source | ✅ | ❌ |
| Simplicity | Medium | High |

## Usage Examples

### parallels-vm Module

#### ISO-based Deployment

```hcl
module "ubuntu_server" {
  source = "./modules/parallels-vm"
  
  name      = "ubuntu-web-server"
  iso_path  = "../output/ubuntu-autoinstall.iso"
  cpus      = 4
  memory    = 8192
  disk_size = 50
  headless  = false
}
```

#### Template-based Deployment

```hcl
module "web_node" {
  source = "./modules/parallels-vm"
  
  name          = "web-node-01"
  template_name = "ubuntu-base-template"
  linked_clone  = true
  cpus          = 2
  memory        = 4096
  
  cloud_init_config = file("${path.module}/cloud-init/web-server.yaml")
}
```

#### PVM Import

```hcl
module "imported_vm" {
  source = "./modules/parallels-vm"
  
  name            = "imported-database"
  pvm_bundle_path = "./templates/ubuntu-db.pvm"
  cpus            = 8
  memory          = 16384
}
```

### vm-template Module

#### Basic Template Clone

```hcl
module "app_server" {
  source = "./modules/vm-template"
  
  vm_name       = "app-server-01"
  template_name = "ubuntu-base-template"
  linked_clone  = true
}
```

#### With Cloud-Init

```hcl
module "web_server" {
  source = "./modules/vm-template"
  
  vm_name       = "web-server-01"
  template_name = "ubuntu-base-template"
  linked_clone  = true
  cpus          = 2
  memory        = 4096
  
  cloud_init_user_data = <<-EOT
    #cloud-config
    hostname: web-01
    packages:
      - nginx
      - certbot
    runcmd:
      - systemctl enable nginx
      - systemctl start nginx
  EOT
}
```

## Module Inputs

### Common Inputs (Both Modules)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name`/`vm_name` | string | required | VM name in Parallels |
| `cpus` | number | 2 | Number of CPU cores |
| `memory` | number | 2048 | RAM in MB |
| `network_mode` | string | "shared" | Network type: shared, host, bridged |
| `headless` | bool | false | Run without GUI |

### parallels-vm Specific

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `iso_path` | string | "" | Path to Ubuntu ISO |
| `template_name` | string | "" | Template to clone |
| `template_uuid` | string | "" | Template UUID |
| `pvm_bundle_path` | string | "" | PVM file to import |
| `disk_size` | number | 20 | Disk size in GB (ISO only) |
| `linked_clone` | bool | true | Use linked clones |
| `cloud_init_config` | string | "" | Cloud-init user-data |

### vm-template Specific

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `template_name` | string | required | Source template |
| `linked_clone` | bool | true | Use linked clones |
| `cloud_init_user_data` | string | "" | Cloud-init config |
| `cloud_init_meta_data` | string | "" | Cloud-init metadata |
| `start_after_create` | bool | true | Auto-start VM |

## Module Outputs

### Common Outputs

| Output | Description |
|--------|-------------|
| `vm_name` | Name of the created VM |
| `vm_id` | Unique identifier |
| `deployment_type` | How VM was created |

### parallels-vm Outputs

```hcl
output "vm_info" {
  value = module.ubuntu_server.vm_info
  # Returns: {
  #   name = "ubuntu-web-server"
  #   id = "ubuntu-web-server-a1b2c3d4"
  #   deployment_type = "iso"
  # }
}
```

### vm-template Outputs

```hcl
output "vm_details" {
  value = module.web_server
  # Returns all module outputs including name, id, status
}
```

## Best Practices

### 1. Choose the Right Module

- **Use `parallels-vm` when**:
  - You need flexibility in deployment source
  - Creating initial VMs from ISO
  - Importing existing PVM bundles
  - Need advanced control

- **Use `vm-template` when**:
  - Always deploying from templates
  - Want simplified configuration
  - Focus on cloud-init customization
  - Standard template workflow

### 2. Resource Sizing

```hcl
# Development
cpus   = 2
memory = 2048

# Production
cpus   = 4
memory = 8192

# Database/Heavy workload
cpus   = 8
memory = 16384
```

### 3. Network Selection

- **shared** (default): NAT with host, internet access
- **host**: Host-only network, isolated
- **bridged**: Direct network access, gets IP from network DHCP

### 4. Cloud-Init Integration

Always use cloud-init for:
- Setting hostnames
- Installing packages
- Configuring services
- Adding users/SSH keys
- Running first-boot scripts

Example cloud-init file structure:
```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.${domain}

users:
  - name: ubuntu
    ssh_authorized_keys:
      - ${ssh_key}
    sudo: ['ALL=(ALL) NOPASSWD:ALL']

packages:
  - docker.io
  - docker-compose

runcmd:
  - systemctl enable docker
  - usermod -aG docker ubuntu
```

### 5. Module Composition

Combine modules for complex deployments:

```hcl
# Create database tier
module "db_nodes" {
  for_each = toset(["db-01", "db-02"])
  source   = "./modules/vm-template"
  
  vm_name       = each.key
  template_name = "ubuntu-db-template"
  cpus          = 4
  memory        = 8192
}

# Create web tier
module "web_nodes" {
  count  = 3
  source = "./modules/vm-template"
  
  vm_name       = "web-${count.index + 1}"
  template_name = "ubuntu-web-template"
  cpus          = 2
  memory        = 4096
}
```

## Troubleshooting

### Module Issues

1. **"Required variable not set"**
   - Ensure all required variables are provided
   - Check variable names match module interface

2. **"Template not found"**
   - Verify template exists: `prlctl list -t`
   - Check template name spelling

3. **"ISO path invalid"**
   - Use absolute paths or correct relative paths
   - Verify ISO file exists

4. **"VM already exists"**
   - Modules auto-remove existing VMs
   - If persists, manually delete: `prlctl delete <name>`

### Performance Tips

1. **Use linked clones** for template deployments (90% faster)
2. **Pre-build templates** with common software installed
3. **Allocate sufficient host resources** (check Activity Monitor)
4. **Use SSDs** for VM storage when possible

## Module Development

### Adding New Features

1. Update variables.tf with new inputs
2. Implement logic in main.tf
3. Add outputs to outputs.tf
4. Update documentation
5. Test with example configuration

### Testing Modules

```bash
# Initialize module
cd modules/parallels-vm
terraform init

# Validate syntax
terraform validate

# Test with example
cd ../../examples/module-test
terraform plan
```

## Related Documentation

- [Parallels Provider Docs](https://registry.terraform.io/providers/parallels/parallels-desktop/latest)
- [OpenTofu Modules Guide](https://opentofu.org/docs/language/modules/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)