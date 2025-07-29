terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.2.0"
    }
  }
}

# Variables for VM configuration
variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "ubuntu-autoinstall"
}

variable "vm_hostname" {
  description = "Hostname for the VM"
  type        = string
  default     = "ubuntu-server"
}

variable "ssh_public_key" {
  description = "SSH public key for the ubuntu user"
  type        = string
  # Example: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ..."
}

variable "vm_cpus" {
  description = "Number of CPUs"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "vm_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "custom_iso_path" {
  description = "Path to the custom autoinstall ISO"
  type        = string
  default     = "../output/ubuntu-22.04.5-autoinstall-arm64.iso"
}

# Cloud-init configuration
locals {
  cloud_init_user_data = yamlencode({
    hostname = var.vm_hostname
    fqdn     = "${var.vm_hostname}.local"
    
    # User configuration
    users = [
      {
        name   = "ubuntu"
        groups = ["adm", "audio", "cdrom", "dialout", "dip", "floppy", "lxd", "netdev", "plugdev", "sudo", "video"]
        sudo   = ["ALL=(ALL) NOPASSWD:ALL"]
        shell  = "/bin/bash"
        lock_passwd = true
        ssh_authorized_keys = [var.ssh_public_key]
      }
    ]
    
    # Package management
    package_update  = true
    package_upgrade = false
    packages = [
      "qemu-guest-agent",
      "net-tools",
      "htop",
      "jq"
    ]
    
    # System configuration
    timezone = "UTC"
    locale   = "en_US.UTF-8"
    
    # Disable SSH password authentication
    ssh_pwauth = false
    
    # Run commands on first boot
    runcmd = [
      "systemctl enable qemu-guest-agent",
      "systemctl start qemu-guest-agent",
      "echo 'VM provisioned by OpenTofu' > /etc/motd"
    ]
    
    # Final message
    final_message = "VM ${var.vm_hostname} is ready!"
  })
  
  cloud_init_meta_data = yamlencode({
    instance-id    = var.vm_name
    local-hostname = var.vm_hostname
  })
}

# Create the VM
resource "parallels-desktop_vm" "ubuntu" {
  name     = var.vm_name
  os_type  = "ubuntu"
  
  # Use custom ISO for installation
  boot_order = ["cdrom0", "hdd0"]
  
  # Hardware configuration
  cpu {
    count = var.vm_cpus
  }
  
  memory {
    size = var.vm_memory
  }
  
  # Storage configuration
  hard_disk {
    size = var.vm_disk_size * 1024  # Convert GB to MB
    type = "expanding"
  }
  
  # CD-ROM with autoinstall ISO
  cdrom {
    enabled = true
    image   = abspath(var.custom_iso_path)
  }
  
  # Network configuration
  network_adapter {
    type = "shared"
  }
  
  # Guest tools
  guest_tools {
    mode = "auto"
  }
  
  # Cloud-init configuration via Parallels
  # This will be passed to the VM during installation
  prlctl {
    set = [
      # Pass cloud-init user-data
      ["--device-set", "cdrom0", "--image", abspath(var.custom_iso_path)],
      
      # Set cloud-init custom data
      # Note: Parallels Desktop provider may handle this differently
      # Check provider documentation for exact syntax
    ]
  }
  
  # Post-installation configuration
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for VM to complete installation
      echo "Waiting for VM to complete autoinstall..."
      sleep 300  # Adjust based on your system
      
      # The VM should now be accessible via SSH
      echo "VM installation complete. You can SSH using:"
      echo "ssh -i <private_key> ubuntu@<vm_ip>"
    EOT
  }
}

# Output VM information
output "vm_name" {
  value = parallels-desktop_vm.ubuntu.name
}

output "vm_id" {
  value = parallels-desktop_vm.ubuntu.id
}

output "connection_info" {
  value = <<-EOT
    VM Name: ${var.vm_name}
    Hostname: ${var.vm_hostname}
    Username: ubuntu
    SSH: ssh -i <your_private_key> ubuntu@<vm_ip>
    
    To get the VM IP address:
    1. Run: prlctl list -f
    2. Or: prlctl exec ${var.vm_name} ip addr show
  EOT
}