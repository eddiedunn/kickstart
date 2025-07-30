# Template-Based VM Deployment Example

This example demonstrates how to deploy multiple VMs from a Parallels template using OpenTofu.

## Prerequisites

1. A prepared Ubuntu VM template (see scripts/prepare-vm-template.sh)
2. OpenTofu installed
3. Parallels Desktop Pro or Business Edition

## Usage

1. First, prepare your existing VM as a template:
   ```bash
   # Make the scripts executable
   chmod +x ../../../scripts/prepare-vm-template.sh
   chmod +x ../../../scripts/create-parallels-template.sh
   
   # Prepare the VM (generalizes it)
   ../../../scripts/prepare-vm-template.sh ubuntu-minimal-test
   
   # Create the template
   ../../../scripts/create-parallels-template.sh ubuntu-minimal-test
   ```

2. Get the template UUID from the output or by running:
   ```bash
   prlctl list --template
   ```

3. Create a `terraform.tfvars` file:
   ```hcl
   template_uuid = "your-template-uuid-here"
   vm_count = 3
   ssh_public_key = "ssh-rsa AAAAB3... your-key"
   ```

4. Deploy the VMs:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

5. Access the VMs:
   ```bash
   # Use the generated SSH config
   ssh -F ssh_config ubuntu-poc-1
   
   # Or use the Ansible inventory
   ansible -i inventory.ini ubuntu_vms -m ping
   ```

## Customization

### Cloud-Init Configuration

Edit `cloud-init.yaml` to customize:
- User accounts and SSH keys
- Installed packages
- Network configuration
- First-boot scripts

### VM Resources

Modify in `main.tf`:
- `cpus`: Number of CPUs per VM
- `memory`: RAM in MB
- `linked_clone`: Use linked clones (saves disk space)

### Scaling

Simply change `vm_count` to deploy more or fewer VMs:
```bash
tofu apply -var="vm_count=10"
```

## Cleanup

To destroy all VMs:
```bash
tofu destroy
```

## Tips

1. **Linked Clones**: Enable `linked_clone = true` to save disk space when deploying many VMs
2. **Template Updates**: To update the base template, modify the original VM and re-run the template creation script
3. **Networking**: VMs use shared networking by default. Change to bridged for direct network access
4. **Performance**: For better performance, disable `headless = false` after initial testing