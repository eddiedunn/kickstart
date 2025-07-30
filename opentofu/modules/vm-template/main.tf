terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
  }
}

locals {
  vm_name = var.vm_name
  
  # Determine source based on what's provided
  source_type = var.template_name != "" ? "template" : (
    var.pvm_path != "" ? "pvm" : (
      var.snapshot_id != "" ? "snapshot" : "none"
    )
  )
  
  # Generate cloud-init ISO if enabled
  cloud_init_iso = var.cloud_init ? "${path.module}/cloud-init-${var.vm_name}.iso" : ""
}

# Generate cloud-init ISO if enabled
resource "null_resource" "cloud_init_iso" {
  count = var.cloud_init ? 1 : 0
  
  triggers = {
    vm_name = var.vm_name
    user_data = var.user_data
    meta_data = var.meta_data
    iso_path = local.cloud_init_iso
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary directory for cloud-init files
      TEMP_DIR=$(mktemp -d)
      
      # Write user-data
      cat > "$TEMP_DIR/user-data" << 'EOF'
      ${var.user_data}
      EOF
      
      # Write meta-data
      cat > "$TEMP_DIR/meta-data" << 'EOF'
      ${var.meta_data}
      EOF
      
      # Create ISO
      if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "${local.cloud_init_iso}" -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data"
      elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -o "${local.cloud_init_iso}" -V cidata -J -r "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data"
      else
        echo "ERROR: Neither genisoimage nor mkisofs found. Install one to create cloud-init ISO."
        exit 1
      fi
      
      # Cleanup
      rm -rf "$TEMP_DIR"
    EOT
  }
  
  provisioner "local-exec" {
    when = destroy
    command = "rm -f '${self.triggers.iso_path}'"
  }
}

# Create VM from template
resource "null_resource" "create_vm" {
  depends_on = [null_resource.cloud_init_iso]
  
  triggers = {
    vm_name = var.vm_name
    source_type = local.source_type
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if VM already exists
      if prlctl list -a | grep -q "^${var.vm_name}\\s"; then
        echo "VM ${var.vm_name} already exists. Stopping and removing..."
        prlctl stop "${var.vm_name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${var.vm_name}"
      fi
      
      # Create VM based on source type
      case "${local.source_type}" in
        template)
          echo "Creating VM from template: ${var.template_name}"
          if [ "${var.linked_clone}" = "true" ]; then
            prlctl clone "${var.template_name}" --name "${var.vm_name}" --linked
          else
            prlctl clone "${var.template_name}" --name "${var.vm_name}"
          fi
          ;;
          
        pvm)
          echo "Importing VM from PVM: ${var.pvm_path}"
          prlctl register "${var.pvm_path}" --regenerate-src-uuid
          # Rename if needed
          SOURCE_NAME=$(basename "${var.pvm_path}" .pvm)
          if [ "$SOURCE_NAME" != "${var.vm_name}" ]; then
            prlctl set "$SOURCE_NAME" --name "${var.vm_name}"
          fi
          ;;
          
        snapshot)
          echo "Creating VM from snapshot: ${var.snapshot_id}"
          # Clone the source VM
          prlctl clone "${var.source_vm}" --name "${var.vm_name}"
          # Switch to snapshot
          prlctl snapshot-switch "${var.vm_name}" --id "${var.snapshot_id}"
          ;;
          
        *)
          echo "ERROR: No valid source specified (template_name, pvm_path, or snapshot_id)"
          exit 1
          ;;
      esac
      
      # Apply hardware customization if specified
      if [ ${var.cpus} -gt 0 ]; then
        prlctl set "${var.vm_name}" --cpus ${var.cpus}
      fi
      
      if [ ${var.memory} -gt 0 ]; then
        prlctl set "${var.vm_name}" --memsize ${var.memory}
      fi
      
      # Attach cloud-init ISO if created
      if [ -f "${local.cloud_init_iso}" ]; then
        echo "Attaching cloud-init ISO..."
        prlctl set "${var.vm_name}" --device-set cdrom0 --image "${abspath(local.cloud_init_iso)}" --connect
      fi
      
      # Configure network
      if [ -n "${var.network_mode}" ]; then
        prlctl set "${var.vm_name}" --device-set net0 --type ${var.network_mode}
      fi
      
      echo "VM ${var.vm_name} created successfully"
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

# Start VM
resource "null_resource" "start_vm" {
  depends_on = [null_resource.create_vm]
  count = var.auto_start ? 1 : 0
  
  triggers = {
    vm_id = null_resource.create_vm.id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting VM ${var.vm_name}..."
      prlctl start "${var.vm_name}"
      
      # Wait for VM to start
      sleep 10
      
      # Check status
      if prlctl list | grep -q "^${var.vm_name}\\s.*running"; then
        echo "VM ${var.vm_name} is running"
      else
        echo "WARNING: VM ${var.vm_name} may have failed to start"
      fi
    EOT
  }
}

# Gather VM information
data "external" "vm_info" {
  depends_on = [null_resource.start_vm, null_resource.create_vm]
  
  program = ["bash", "-c", <<-EOT
    VM_NAME="${var.vm_name}"
    
    # Get VM info
    if prlctl list -a | grep -q "^$VM_NAME\\s"; then
      STATUS=$(prlctl list -i "$VM_NAME" | grep "State:" | awk '{print $2}')
      UUID=$(prlctl list -i "$VM_NAME" | grep "UUID:" | awk '{print $2}')
      
      # Try to get IP
      IP=""
      if [ "$STATUS" = "running" ]; then
        IP=$(prlctl exec "$VM_NAME" "ip -4 addr show scope global" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "")
      fi
      
      # Output JSON
      echo "{\"name\":\"$VM_NAME\",\"status\":\"$STATUS\",\"uuid\":\"$UUID\",\"ip\":\"$IP\"}"
    else
      echo "{\"name\":\"$VM_NAME\",\"status\":\"not_found\",\"uuid\":\"\",\"ip\":\"\"}"
    fi
  EOT
  ]
}