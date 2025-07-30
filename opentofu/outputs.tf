# Outputs for ISO-based VM Deployments
#
# These outputs provide useful information and commands after deployment.
# Access outputs with: tofu output <output_name>
# For JSON format: tofu output -json <output_name>

# VM Configuration Details
# Shows the configuration used for each deployed VM
output "vm_info" {
  description = "Configuration details for each deployed VM"
  value = {
    for k, vm in local.vms : k => {
      name      = vm.name        # VM name in Parallels
      cpus      = vm.cpus        # Allocated CPU cores
      memory    = vm.memory      # RAM in MB
      disk_size = vm.disk_size   # Disk size in GB
      iso_path  = vm.iso_path    # Source ISO used
      network   = vm.network     # Network type (shared/host/bridged)
    }
  }
}

# VM Status Information
# Note: This is static output. Run 'tofu refresh' to update
output "vm_status" {
  description = "Current VM status placeholder (run 'tofu refresh' for live data)"
  value = {
    for k, vm in local.vms : k => {
      name = vm.name
      info = "Run './scripts/status.sh' for real-time status"
    }
  }
}

# SSH Connection Commands
# Ready-to-use SSH commands for each VM
# Note: VMs must complete installation before SSH is available
output "ssh_commands" {
  description = "SSH commands to connect to VMs (after installation completes)"
  value = {
    for k, vm in local.vms : k => 
      "ssh ubuntu@$(prlctl exec ${vm.name} \"ip -4 addr show scope global\" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1)"
  }
  
  # Example usage:
  # eval $(tofu output -raw ssh_commands | jq -r '.web')
}

# Parallels CLI Reference
# Common commands for VM management outside of Terraform
output "useful_commands" {
  description = "Useful Parallels Desktop CLI commands for VM management"
  value = {
    "list_all_vms"      = "prlctl list -a"
    "list_running_vms"  = "prlctl list"
    "get_vm_details"    = "prlctl list -i <vm-name>"
    "get_vm_ip"         = "prlctl exec <vm-name> \"ip -4 addr show\" | grep inet"
    "start_vm"          = "prlctl start <vm-name>"
    "stop_vm"           = "prlctl stop <vm-name>"
    "restart_vm"        = "prlctl restart <vm-name>"
    "delete_vm"         = "prlctl delete <vm-name>"
    "vm_console"        = "Open Parallels Desktop app and click on VM"
    "check_cloud_init"  = "prlctl exec <vm-name> \"cloud-init status\""
  }
}

# Deployment Summary
# Provides a comprehensive overview after deployment
output "deployment_summary" {
  description = "Human-readable deployment summary with next steps"
  value = <<-EOT
    ================================================================================
    Deployment Complete!
    ================================================================================
    
    VMs Deployed: ${length(local.vms)}
    
    VM Specifications:
    ${join("\n    ", [for k, vm in local.vms : format("%-20s %2d CPUs, %5d MB RAM, %3d GB disk", "${vm.name}:", vm.cpus, vm.memory, vm.disk_size)])}
    
    Network Configuration: ${length(local.vms) > 0 ? values(local.vms)[0].network : "N/A"}
    
    --------------------------------------------------------------------------------
    NEXT STEPS:
    --------------------------------------------------------------------------------
    
    1. Monitor Installation Progress:
       ./scripts/status.sh --watch
       
       Installation typically takes 5-10 minutes depending on:
       - VM specifications
       - Network speed (for package downloads)
       - Host system performance
    
    2. Get VM IP Addresses:
    ${join("\n    ", [for k, vm in local.vms : "prlctl exec ${vm.name} \"ip -4 addr show\" | grep inet"])}
    
    3. Connect via SSH (after installation):
    ${join("\n    ", [for k, vm in local.vms : "ssh ubuntu@<vm-ip>  # Get IP from step 2"])}
    
    4. Create Templates (optional):
       After configuring a VM, create a template for faster deployments:
    ${join("\n    ", [for k, vm in local.vms : "./scripts/manage-templates.sh create ${vm.name}"])}
    
    --------------------------------------------------------------------------------
    USEFUL COMMANDS:
    --------------------------------------------------------------------------------
    
    Check Status:     ./scripts/status.sh
    Open Console:     Click VM in Parallels Desktop app
    Stop All VMs:     tofu run prlctl stop
    Destroy All:      tofu destroy
    
    --------------------------------------------------------------------------------
    TROUBLESHOOTING:
    --------------------------------------------------------------------------------
    
    - If SSH fails: Wait for installation to complete (check console)
    - If no IP: Verify VM network settings and DHCP
    - If slow: Check host resources (CPU, RAM, disk I/O)
    
    For detailed logs:
    prlctl exec <vm-name> "sudo journalctl -u cloud-init"
  EOT
  
  depends_on = [null_resource.vm_info]
}