output "vm_info" {
  description = "Information about deployed VMs"
  value = {
    for k, vm in parallels-desktop_vm.ubuntu : k => {
      name   = vm.name
      id     = vm.id
      status = "deployed"
    }
  }
}

output "ssh_commands" {
  description = "SSH commands to connect to VMs"
  value = {
    for k, vm in parallels-desktop_vm.ubuntu : k => 
      "ssh ubuntu@$(prlctl exec ${vm.name} ip addr show | grep -E 'inet .* scope global' | head -1 | awk '{print $2}' | cut -d/ -f1)"
  }
}

output "deployment_summary" {
  description = "Deployment summary"
  value = <<-EOT
    Deployment Complete!
    ===================
    
    VMs deployed: ${length(parallels-desktop_vm.ubuntu)}
    
    To get VM IP addresses:
    ${join("\n    ", [for k, vm in parallels-desktop_vm.ubuntu : "prlctl exec ${vm.name} ip addr show | grep 'inet ' | grep -v '127.0.0.1'"])}
    
    To list all VMs:
      prlctl list -a
    
    To stop all VMs:
      tofu destroy
    
    To check VM status:
      ./scripts/status.sh
    
    Note: VMs may take a few minutes to complete autoinstall and become accessible via SSH.
  EOT
}