terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.2.0"
    }
  }
}

# Provider configuration
provider "parallels-desktop" {
  # Provider will use default Parallels Desktop installation
}

# Local values for SSH key detection
locals {
  ssh_public_key = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : (
    fileexists("${path.home}/.ssh/id_ed25519.pub") ? file("${path.home}/.ssh/id_ed25519.pub") :
    fileexists("${path.home}/.ssh/id_rsa.pub") ? file("${path.home}/.ssh/id_rsa.pub") :
    fileexists("${path.home}/.ssh/id_ecdsa.pub") ? file("${path.home}/.ssh/id_ecdsa.pub") : ""
  )
  
  # Normalize VM definitions
  vms = length(var.vm_definitions) > 0 ? var.vm_definitions : {
    "default" = {
      name        = "ubuntu-server"
      cpus        = var.default_cpus
      memory      = var.default_memory
      disk_size   = var.default_disk_size
      iso_path    = var.default_iso_path
      network     = "shared"
      start_after = []
    }
  }
}

# Create VMs based on definitions
resource "parallels-desktop_vm" "ubuntu" {
  for_each = local.vms
  
  name = each.value.name
  
  # Specify Ubuntu as the OS type for optimal settings
  os_type = "ubuntu"
  
  # Hardware configuration
  cpu {
    count = each.value.cpus
  }
  
  memory {
    size = each.value.memory
  }
  
  # Storage configuration
  hard_disk {
    size = each.value.disk_size * 1024  # Convert GB to MB
    type = "expanding"
  }
  
  # Boot configuration
  boot_order = ["cdrom0", "hdd0"]
  
  # CD-ROM with autoinstall ISO
  cdrom {
    enabled = true
    image   = abspath(each.value.iso_path)
  }
  
  # Network adapter
  network_adapter {
    type = each.value.network
  }
  
  # Guest tools
  guest_tools {
    mode = "auto"
  }
  
  # Additional VM settings via prlctl
  prlctl {
    # Create VM with proper architecture settings
    create = [
      each.value.name,
      "--distribution", "ubuntu",
      "--no-hdd"  # We'll add disk separately
    ]
    
    # Configure VM settings
    set = concat([
      # Add disk
      ["--device-add", "hdd", "--size", "${each.value.disk_size * 1024}", "--type", "expanding"],
      
      # Set firmware type to EFI (works for both ARM64 and x86_64)
      ["--firmware-type", "efi"],
      
      # Set boot device
      ["--device-set", "cdrom0", "--image", abspath(each.value.iso_path)],
      ["--device-bootorder", "cdrom0 hdd0"],
      
      # Window and behavior settings
      ["--startup-view", var.headless ? "headless" : "window"],
      ["--on-shutdown", "close"],
      
      # Resources
      ["--cpus", tostring(each.value.cpus)],
      ["--memsize", tostring(each.value.memory)],
      
      # Features
      ["--time-sync", "on"],
      ["--shared-clipboard", var.headless ? "off" : "on"],
      ["--shared-cloud", "off"],
      
      # Disable auto-compress
      ["--auto-compress", "off"],
      
      # Set video memory
      ["--videosize", "32"]
    ],
    # Conditionally add nested virtualization
    var.enable_nested_virt ? [["--nested-virt", "on"]] : [])
  }
  
  # Start VM after creation
  start_after_create = true
  
  # Dependencies between VMs
  depends_on = [
    for dep in each.value.start_after : parallels-desktop_vm.ubuntu[dep]
  ]
  
  # Lifecycle management
  lifecycle {
    # Replace VM if critical settings change
    replace_triggered_by = [
      parallels-desktop_vm.ubuntu[each.key].prlctl
    ]
  }
}

# Post-deployment provisioner for getting VM IPs
resource "null_resource" "vm_status" {
  for_each = parallels-desktop_vm.ubuntu
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for VM ${each.value.name} to complete installation..."
      sleep 10
    EOT
  }
  
  depends_on = [parallels-desktop_vm.ubuntu]
}