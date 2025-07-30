output "vm_name" {
  description = "Name of the VM"
  value       = var.name
}

output "vm_uuid" {
  description = "UUID of the VM"
  value       = data.external.vm_info.result.uuid
}

output "vm_ip" {
  description = "IP address of the VM"
  value       = data.external.vm_info.result.ip
}

output "vm_status" {
  description = "Current status of the VM"
  value       = data.external.vm_info.result.status
}

output "deployment_method" {
  description = "Method used to deploy the VM"
  value = local.deploy_from_template ? "template" : (
    local.deploy_from_bundle ? "bundle" : "iso"
  )
}