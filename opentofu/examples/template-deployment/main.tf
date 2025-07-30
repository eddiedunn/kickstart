terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.3.0"
    }
  }
}

# Variables for template deployment
variable "template_uuid" {
  description = "UUID of your Ubuntu template"
  type        = string
  # Set this after creating your template
  # Example: default = "12345678-1234-1234-1234-123456789012"
}

variable "vm_count" {
  description = "Number of VMs to deploy"
  type        = number
  default     = 3
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

# Deploy multiple VMs from template
module "ubuntu_vms" {
  source = "../../modules/parallels-vm"
  
  count = var.vm_count
  
  name          = "ubuntu-poc-${count.index + 1}"
  template_uuid = var.template_uuid
  linked_clone  = true
  
  cpus     = 2
  memory   = 2048
  headless = false
  
  # Cloud-init configuration for each VM
  cloud_init_config = templatefile("${path.module}/cloud-init.yaml", {
    hostname       = "ubuntu-poc-${count.index + 1}"
    domain         = "local"
    timezone       = "UTC"
    ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub")
    template_name  = "ubuntu-22.04-template"
  })
}

# Output VM information
output "vm_details" {
  description = "Details of deployed VMs"
  value = {
    for idx, vm in module.ubuntu_vms : vm.vm_name => {
      uuid   = vm.vm_uuid
      ip     = vm.vm_ip
      status = vm.vm_status
    }
  }
}

# Generate SSH config
resource "local_file" "ssh_config" {
  filename = "${path.module}/ssh_config"
  content = join("\n", [
    for idx, vm in module.ubuntu_vms : <<-EOT
    Host ${vm.vm_name}
      HostName ${vm.vm_ip}
      User ubuntu
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
    EOT
  ])
}

# Create inventory file for Ansible
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"
  content = join("\n", concat(
    ["[ubuntu_vms]"],
    [for idx, vm in module.ubuntu_vms : "${vm.vm_name} ansible_host=${vm.vm_ip} ansible_user=ubuntu"]
  ))
}