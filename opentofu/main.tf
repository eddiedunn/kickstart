terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

# Provider configuration
provider "parallels-desktop" {
  # Provider will use default Parallels Desktop installation
}

# Local values for SSH key detection
locals {
  home_dir = pathexpand("~")
  ssh_public_key = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : (
    fileexists("${pathexpand("~")}/.ssh/id_ed25519.pub") ? file("${pathexpand("~")}/.ssh/id_ed25519.pub") :
    fileexists("${pathexpand("~")}/.ssh/id_rsa.pub") ? file("${pathexpand("~")}/.ssh/id_rsa.pub") :
    fileexists("${pathexpand("~")}/.ssh/id_ecdsa.pub") ? file("${pathexpand("~")}/.ssh/id_ecdsa.pub") : ""
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
      if [[ "$(uname -m)" == "arm64" ]]; then
        prlctl create "${each.value.name}" \
          --distribution ubuntu \
          --no-hdd
      else
        prlctl create "${each.value.name}" \
          --distribution ubuntu \
          --no-hdd
      fi
      
      # Configure hardware
      prlctl set "${each.value.name}" \
        --cpus ${each.value.cpus} \
        --memsize ${each.value.memory} \
        --startup-view ${var.headless ? "headless" : "window"} \
        --on-shutdown close \
        --time-sync on \
        --shared-clipboard ${var.headless ? "off" : "on"} \
        --shared-cloud off \
        --auto-compress off \
        --videosize 32
      
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

# Start VMs
resource "null_resource" "start_vm" {
  for_each = local.vms
  
  triggers = {
    vm_id = null_resource.create_vm[each.key].id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting VM ${each.value.name}..."
      prlctl start "${each.value.name}"
      
      # Give VM time to boot
      sleep 5
      
      # Check status
      if prlctl list -i | grep -q "^${each.value.name}\\s"; then
        echo "VM ${each.value.name} is running"
      else
        echo "WARNING: VM ${each.value.name} may have failed to start"
      fi
    EOT
  }
  
  depends_on = [null_resource.create_vm]
}

# Wait for installation to complete
resource "null_resource" "wait_for_installation" {
  for_each = local.vms
  
  triggers = {
    vm_id = null_resource.start_vm[each.key].id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ${each.value.name} to complete installation..."
      echo "This may take 5-10 minutes depending on your hardware."
      
      # Wait for VM to get an IP (indicates it's booted)
      MAX_WAIT=600  # 10 minutes
      WAITED=0
      
      while [ $WAITED -lt $MAX_WAIT ]; do
        # Try to get IP address
        IP=$(prlctl exec "${each.value.name}" "ip -4 addr show scope global" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
        
        if [ -n "$IP" ]; then
          echo "VM ${each.value.name} has IP address: $IP"
          
          # Check if cloud-init has finished
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