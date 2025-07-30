# main.tf - ISO-based VM Deployment Configuration
#
# This configuration deploys Ubuntu VMs from custom autoinstall ISOs.
# It handles VM creation, configuration, and lifecycle management.
# For template-based deployments, see main-templates.tf

terraform {
  required_providers {
    # Parallels Desktop provider for VM management
    # Supports VM creation, configuration, and control
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.2.0"
    }
    
    # Null provider for executing local commands
    # Used for VM operations not supported by Parallels provider
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    
    # Random provider for generating unique identifiers
    # Ensures VMs can be recreated without conflicts
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

# Provider configuration
provider "parallels-desktop" {
  # Provider automatically detects Parallels Desktop installation
  # Default location: /Applications/Parallels Desktop.app
  # No explicit configuration needed for standard installations
}

# Local values for SSH key detection and VM configuration
locals {
  # Expand home directory path for cross-platform compatibility
  home_dir = pathexpand("~")
  
  # SSH key detection with priority order:
  # 1. User-specified path (if provided)
  # 2. Ed25519 key (most secure, recommended)
  # 3. RSA key (widely compatible)
  # 4. ECDSA key (alternative)
  # 5. Empty string if no keys found
  ssh_public_key = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : (
    fileexists("${pathexpand("~")}/.ssh/id_ed25519.pub") ? file("${pathexpand("~")}/.ssh/id_ed25519.pub") :
    fileexists("${pathexpand("~")}/.ssh/id_rsa.pub") ? file("${pathexpand("~")}/.ssh/id_rsa.pub") :
    fileexists("${pathexpand("~")}/.ssh/id_ecdsa.pub") ? file("${pathexpand("~")}/.ssh/id_ecdsa.pub") : ""
  )
  
  # Normalize VM definitions with fallback to defaults
  # If no VMs defined in terraform.tfvars, create a single default VM
  # This ensures the configuration always produces at least one VM
  vms = length(var.vm_definitions) > 0 ? var.vm_definitions : {
    "default" = {
      name        = "ubuntu-server"          # VM name in Parallels
      cpus        = var.default_cpus         # Number of CPU cores
      memory      = var.default_memory       # RAM in MB
      disk_size   = var.default_disk_size    # Disk in GB
      iso_path    = var.default_iso_path     # Path to autoinstall ISO
      network     = "shared"                 # NAT networking
      start_after = []                       # No dependencies
    }
  }
}

# Generate unique IDs for VMs to handle recreation
resource "random_id" "vm" {
  for_each = local.vms
  byte_length = 4
  
  keepers = {
    # Force recreation if these change
    name = each.value.name
    iso_path = each.value.iso_path
  }
}

# Create VMs using null_resource and prlctl commands
resource "null_resource" "create_vm" {
  for_each = local.vms
  
  triggers = {
    vm_id = random_id.vm[each.key].hex
    vm_name = each.value.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if VM already exists
      if prlctl list -a | grep -q "^${each.value.name}\\s"; then
        echo "VM ${each.value.name} already exists. Stopping and removing..."
        prlctl stop "${each.value.name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${each.value.name}"
      fi
      
      echo "Creating VM ${each.value.name}..."
      
      # Create the VM with proper architecture detection
      # ARM64 (Apple Silicon) and x86_64 (Intel) are both supported
      if [[ "$(uname -m)" == "arm64" ]]; then
        prlctl create "${each.value.name}" \
          --distribution ubuntu \
          --no-hdd  # We'll add disk separately for size control
      else
        prlctl create "${each.value.name}" \
          --distribution ubuntu \
          --no-hdd
      fi
      
      # Configure VM hardware and behavior
      prlctl set "${each.value.name}" \
        --cpus ${each.value.cpus} \           # CPU cores
        --memsize ${each.value.memory} \      # RAM in MB
        --startup-view ${var.headless ? "headless" : "window"} \
        --on-shutdown close \                 # Close VM window on shutdown
        --time-sync on \                      # Sync time with host
        --shared-clipboard ${var.headless ? "off" : "on"} \
        --shared-cloud off \                   # Disable iCloud integration
        --auto-compress off \                  # Better performance
        --videosize 32                          # Video memory in MB
      
      # Add disk
      prlctl set "${each.value.name}" \
        --device-add hdd \
        --size ${each.value.disk_size * 1024}
      
      # Set firmware to EFI
      prlctl set "${each.value.name}" \
        --efi-boot on
      
      # Configure network
      prlctl set "${each.value.name}" \
        --device-set net0 \
        --type ${each.value.network}
      
      # Attach ISO
      ISO_PATH="${abspath(each.value.iso_path)}"
      if [ ! -f "$ISO_PATH" ]; then
        echo "ERROR: ISO file not found at $ISO_PATH"
        exit 1
      fi
      
      prlctl set "${each.value.name}" \
        --device-set cdrom0 \
        --image "$ISO_PATH" \
        --connect
      
      # Set boot order
      prlctl set "${each.value.name}" \
        --device-bootorder "cdrom0 hdd0"
      
      # ARM64-specific optimizations
      if [[ "$(uname -m)" == "arm64" ]]; then
        prlctl set "${each.value.name}" \
          --adaptive-hypervisor on
      fi
      
      # Enable nested virtualization if requested
      %{ if var.enable_nested_virt ~}
      prlctl set "${each.value.name}" \
        --nested-virt on
      %{ endif ~}
      
      echo "VM ${each.value.name} created successfully"
    EOT
  }
  
  # Destroy provisioner ensures clean VM removal
  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      if prlctl list -a | grep -q "^${self.triggers.vm_name}\\s"; then
        echo "Stopping and removing VM ${self.triggers.vm_name}..."
        prlctl stop "${self.triggers.vm_name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${self.triggers.vm_name}"
      fi
    EOT
  }
}

# Start VMs after creation
# Separate resource ensures VM is fully configured before starting
resource "null_resource" "start_vm" {
  for_each = local.vms
  
  triggers = {
    # Depend on VM creation to ensure proper ordering
    vm_id = null_resource.create_vm[each.key].id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting VM ${each.value.name}..."
      prlctl start "${each.value.name}"
      
      # Give VM time to initialize
      sleep 5
      
      # Verify VM started successfully
      if prlctl list -i | grep -q "^${each.value.name}\\s"; then
        echo "VM ${each.value.name} is running"
      else
        echo "WARNING: VM ${each.value.name} may have failed to start"
      fi
    EOT
  }
  
  depends_on = [null_resource.create_vm]
}

# Wait for Ubuntu autoinstall to complete
# This resource monitors the VM until cloud-init finishes
resource "null_resource" "wait_for_installation" {
  for_each = local.vms
  
  triggers = {
    # Run after VM starts
    vm_id = null_resource.start_vm[each.key].id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ${each.value.name} to complete installation..."
      echo "This may take 5-10 minutes depending on your hardware."
      
      # Wait for VM to get an IP (indicates it's booted)
      MAX_WAIT=600  # 10 minutes timeout
      WAITED=0
      
      while [ $WAITED -lt $MAX_WAIT ]; do
        # Try to get IP address from inside the VM
        # This regex extracts IPv4 addresses only
        IP=$(prlctl exec "${each.value.name}" "ip -4 addr show scope global" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
        
        if [ -n "$IP" ]; then
          echo "VM ${each.value.name} has IP address: $IP"
          
          # Check if cloud-init has finished
          # The boot-finished file is created when cloud-init completes
          if prlctl exec "${each.value.name}" "test -f /var/lib/cloud/instance/boot-finished" 2>/dev/null; then
            echo "Installation completed for ${each.value.name}"
            break
          fi
        fi
        
        echo -ne "\rWaiting... $WAITED/$MAX_WAIT seconds"
        sleep 10
        WAITED=$((WAITED + 10))
      done
      
      echo ""
      
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "WARNING: Maximum wait time reached for ${each.value.name}"
        echo "VM may still be installing. Check manually with: prlctl list -i"
      fi
    EOT
  }
  
  depends_on = [null_resource.start_vm]
}

# Gather VM information
resource "null_resource" "vm_info" {
  for_each = local.vms
  
  triggers = {
    vm_id = null_resource.wait_for_installation[each.key].id
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Get VM info and save to file
      VM_NAME="${each.value.name}"
      INFO_FILE="${path.module}/.vm_info_${each.key}.json"
      
      # Get VM status
      STATUS=$(prlctl list -i --json | jq -r ".[] | select(.name == \"$VM_NAME\") | .status" || echo "unknown")
      
      # Get IP address
      IP=$(prlctl exec "$VM_NAME" "ip -4 addr show scope global" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "")
      
      # Get VM UUID
      UUID=$(prlctl list -i --json | jq -r ".[] | select(.name == \"$VM_NAME\") | .uuid" || echo "")
      
      # Create JSON info file
      cat > "$INFO_FILE" <<EOF
      {
        "name": "$VM_NAME",
        "status": "$STATUS",
        "ip": "$IP",
        "uuid": "$UUID",
        "cpus": ${each.value.cpus},
        "memory": ${each.value.memory},
        "disk_size": ${each.value.disk_size}
      }
      EOF
    EOT
  }
  
  depends_on = [null_resource.wait_for_installation]
}