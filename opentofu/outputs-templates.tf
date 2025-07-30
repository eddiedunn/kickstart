# Additional outputs for template-based deployments

output "template_vm_info" {
  description = "Information about template-based VMs"
  value = {
    for k, v in var.vm_template_definitions : k => {
      name         = v.name
      type         = v.source_type
      source       = v.source_name
      cloud_init   = v.cloud_init
      linked_clone = v.source_type == "template" ? v.linked_clone : null
      module_output = module.template_vms[k]
    }
  }
}

output "all_vms_summary" {
  description = "Summary of all deployed VMs (ISO and template-based)"
  value = {
    total_vms     = length(local.all_vms)
    iso_vms       = length([for k, v in local.all_vms : k if v.type == "iso"])
    template_vms  = length([for k, v in local.all_vms : k if v.type == "template"])
    vms = { for k, v in local.all_vms : k => {
      name   = v.name
      type   = v.type
      source = v.source
      specs  = "${v.cpus} CPUs, ${v.memory}MB RAM${v.disk_size != null ? format(", %dGB disk", v.disk_size) : ""}"
    }}
  }
}

output "template_deployment_commands" {
  description = "Useful commands for template-based VMs"
  value = {
    list_templates = "prlctl list -t"
    list_snapshots = "prlctl snapshot-list <vm-name>"
    create_template = "prlctl set <vm-name> --template on"
    remove_template = "prlctl set <vm-name> --template off"
    export_pvm = "prlctl backup <vm-name> -f <output.pvm>"
    import_pvm = "prlctl restore <path/to/backup.pvm>"
    take_snapshot = "prlctl snapshot <vm-name> -n <snapshot-name>"
  }
}

output "cloud_init_status" {
  description = "Cloud-init status commands for template VMs"
  value = {
    for k, v in var.vm_template_definitions : k => 
      v.cloud_init ? "prlctl exec ${v.name} 'cloud-init status'" : "N/A - cloud-init disabled"
  }
}