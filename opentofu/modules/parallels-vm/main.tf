terraform {
  required_providers {
    parallels-desktop = {
      source  = "parallels/parallels-desktop"
      version = "~> 0.3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
}

# Local values for deployment logic
locals {
  # Determine deployment method
  deploy_from_template = var.template_uuid != "" || var.template_name != ""
  deploy_from_bundle   = var.pvm_bundle_path != ""
  deploy_from_iso      = var.iso_path != ""
  
  # VM unique identifier
  vm_id = "${var.name}-${substr(md5(timestamp()), 0, 8)}"
}

# Deploy from Template UUID or Name
resource "null_resource" "deploy_from_template" {
  count = local.deploy_from_template ? 1 : 0
  
  triggers = {
    vm_name = var.name
    template_id = var.template_uuid != "" ? var.template_uuid : var.template_name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if VM already exists
      if prlctl list -a | grep -q "^${var.name}\\s"; then
        echo "VM ${var.name} already exists. Stopping and removing..."
        prlctl stop "${var.name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${var.name}"
      fi
      
      # Clone from template
      echo "Cloning VM ${var.name} from template..."
      TEMPLATE_ID="${var.template_uuid != "" ? var.template_uuid : var.template_name}"
      
      prlctl clone "$TEMPLATE_ID" \
        --name "${var.name}" \
        ${var.linked_clone ? "--linked" : ""}
      
      # Configure VM hardware
      prlctl set "${var.name}" \
        --cpus ${var.cpus} \
        --memsize ${var.memory} \
        --startup-view ${var.headless ? "headless" : "window"} \
        --on-shutdown close
      
      # Apply cloud-init if provided
      %{ if var.cloud_init_config != "" ~}
      # Create cloud-init ISO
      CLOUD_INIT_DIR=$(mktemp -d)
      echo '${var.cloud_init_config}' > "$CLOUD_INIT_DIR/user-data"
      echo "instance-id: ${local.vm_id}" > "$CLOUD_INIT_DIR/meta-data"
      
      # Generate ISO
      if command -v genisoimage &> /dev/null; then
        genisoimage -output "$CLOUD_INIT_DIR/cloud-init.iso" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
      else
        hdiutil makehybrid -o "$CLOUD_INIT_DIR/cloud-init.iso" -hfs -joliet -iso -default-volume-name cidata "$CLOUD_INIT_DIR"
      fi
      
      # Attach cloud-init ISO
      prlctl set "${var.name}" \
        --device-add cdrom \
        --image "$CLOUD_INIT_DIR/cloud-init.iso" \
        --connect
      %{ endif ~}
      
      echo "VM ${var.name} cloned successfully from template"
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

# Deploy from PVM Bundle
resource "null_resource" "deploy_from_bundle" {
  count = local.deploy_from_bundle ? 1 : 0
  
  triggers = {
    vm_name = var.name
    bundle_path = var.pvm_bundle_path
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if VM already exists
      if prlctl list -a | grep -q "^${var.name}\\s"; then
        echo "VM ${var.name} already exists. Stopping and removing..."
        prlctl stop "${var.name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${var.name}"
      fi
      
      # Import PVM bundle
      echo "Importing VM ${var.name} from bundle ${var.pvm_bundle_path}..."
      prlctl register "${var.pvm_bundle_path}" --force
      
      # Get the original name from the bundle
      ORIG_NAME=$(prlctl list -a --json | jq -r '.[] | select(.Home | contains("${var.pvm_bundle_path}")) | .name')
      
      # Rename if needed
      if [ "$ORIG_NAME" != "${var.name}" ]; then
        prlctl set "$ORIG_NAME" --name "${var.name}"
      fi
      
      # Configure VM hardware
      prlctl set "${var.name}" \
        --cpus ${var.cpus} \
        --memsize ${var.memory} \
        --startup-view ${var.headless ? "headless" : "window"} \
        --on-shutdown close
      
      echo "VM ${var.name} imported successfully from bundle"
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

# Deploy from ISO (existing method)
resource "null_resource" "deploy_from_iso" {
  count = local.deploy_from_iso && !local.deploy_from_template && !local.deploy_from_bundle ? 1 : 0
  
  triggers = {
    vm_name = var.name
    iso_path = var.iso_path
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if VM already exists
      if prlctl list -a | grep -q "^${var.name}\\s"; then
        echo "VM ${var.name} already exists. Stopping and removing..."
        prlctl stop "${var.name}" --kill 2>/dev/null || true
        sleep 2
        prlctl delete "${var.name}"
      fi
      
      # Create new VM
      echo "Creating VM ${var.name} from ISO..."
      prlctl create "${var.name}" \
        --distribution ubuntu \
        --no-hdd
      
      # Configure hardware
      prlctl set "${var.name}" \
        --cpus ${var.cpus} \
        --memsize ${var.memory} \
        --startup-view ${var.headless ? "headless" : "window"} \
        --on-shutdown close \
        --efi-boot on
      
      # Add disk
      prlctl set "${var.name}" \
        --device-add hdd \
        --size ${var.disk_size * 1024}
      
      # Attach ISO
      prlctl set "${var.name}" \
        --device-set cdrom0 \
        --image "${var.iso_path}" \
        --connect
      
      # Set boot order
      prlctl set "${var.name}" \
        --device-bootorder "cdrom0 hdd0"
      
      echo "VM ${var.name} created successfully from ISO"
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
  triggers = {
    vm_id = coalesce(
      try(null_resource.deploy_from_template[0].id, ""),
      try(null_resource.deploy_from_bundle[0].id, ""),
      try(null_resource.deploy_from_iso[0].id, "")
    )
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting VM ${var.name}..."
      prlctl start "${var.name}"
      
      # Wait for VM to boot
      sleep 10
      
      # Check status
      if prlctl list -i | grep -q "^${var.name}\\s"; then
        echo "VM ${var.name} is running"
      else
        echo "WARNING: VM ${var.name} may have failed to start"
      fi
    EOT
  }
  
  depends_on = [
    null_resource.deploy_from_template,
    null_resource.deploy_from_bundle,
    null_resource.deploy_from_iso
  ]
}

# Get VM information
data "external" "vm_info" {
  program = ["bash", "-c", <<-EOT
    VM_NAME="${var.name}"
    
    # Get VM info
    STATUS=$(prlctl list -i --json | jq -r ".[] | select(.name == \"$VM_NAME\") | .status" || echo "unknown")
    UUID=$(prlctl list -i --json | jq -r ".[] | select(.name == \"$VM_NAME\") | .uuid" || echo "")
    IP=$(prlctl exec "$VM_NAME" "ip -4 addr show scope global" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "")
    
    # Output JSON
    cat <<EOF
    {
      "name": "$VM_NAME",
      "status": "$STATUS",
      "uuid": "$UUID",
      "ip": "$IP"
    }
    EOF
  EOT
  ]
  
  depends_on = [null_resource.start_vm]
}