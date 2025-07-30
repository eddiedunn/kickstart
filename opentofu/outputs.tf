output "vm_info" {
  description = "Information about deployed VMs"
  value = {
    for k, vm in local.vms : k => {
      name      = vm.name
      cpus      = vm.cpus
      memory    = vm.memory
      disk_size = vm.disk_size
      iso_path  = vm.iso_path
      network   = vm.network
    }
  }
}

output "vm_status" {
  description = "Current status of VMs (run 'tofu refresh' to update)"
  value = {
    for k, vm in local.vms : k => {
      name = vm.name
      info = "Run 'prlctl list -i' to see current status"
    }
  }
}

output "ssh_commands" {
  description = "SSH commands to connect to VMs"
  value = {
    for k, vm in local.vms : k => 
      "ssh ubuntu@$(prlctl exec ${vm.name} \"ip -4 addr show scope global\" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1)"
  }
}

output "useful_commands" {
  description = "Useful commands for managing VMs"
  value = {
    "list_vms"     = "prlctl list -a"
    "list_running" = "prlctl list -i"
    "get_vm_ip"    = "prlctl exec <vm-name> \"ip -4 addr show scope global\" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'"
    "stop_vm"      = "prlctl stop <vm-name>"
    "start_vm"     = "prlctl start <vm-name>"
    "delete_vm"    = "prlctl delete <vm-name>"
    "vm_info"      = "prlctl list -i --json"
  }
}

output "deployment_summary" {
  description = "Deployment summary"
  value = <<-EOT
    Deployment Complete!
    ===================
    
    VMs configured: ${length(local.vms)}
    
    VM Details:
    ${join("\n    ", [for k, vm in local.vms : "- ${vm.name}: ${vm.cpus} CPUs, ${vm.memory}MB RAM, ${vm.disk_size}GB disk"])}
    
    To get VM IP addresses:
    ${join("\n    ", [for k, vm in local.vms : "prlctl exec ${vm.name} \"ip -4 addr show scope global\" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'"])}
    
    To connect via SSH (after installation completes):
    ${join("\n    ", [for k, vm in local.vms : "ssh ubuntu@$(prlctl exec ${vm.name} \"ip -4 addr show scope global\" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1)"])}
    
    To check VM status:
      ./scripts/status.sh
    
    To destroy all VMs:
      tofu destroy
    
    Note: VMs may take 5-10 minutes to complete Ubuntu autoinstall.
          Check installation progress by opening the VM console in Parallels Desktop.
  EOT
  
  depends_on = [null_resource.vm_info]
}