output "vm_name" {
  description = "Name of the created VM"
  value       = var.vm_name
}

output "vm_uuid" {
  description = "UUID of the created VM"
  value       = try(data.external.vm_info.result.uuid, "")
}

output "vm_status" {
  description = "Current status of the VM"
  value       = try(data.external.vm_info.result.status, "unknown")
}

output "vm_ip" {
  description = "IP address of the VM (if running)"
  value       = try(data.external.vm_info.result.ip, "")
}

output "source_type" {
  description = "Type of source used to create the VM"
  value       = local.source_type
}