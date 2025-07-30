# Template-specific variables for VM deployments

variable "template_vms" {
  description = "Map of VMs to create from templates"
  type = map(object({
    template_name = string
    cpus          = optional(number, 2)
    memory        = optional(number, 4096)
    network_mode  = optional(string, "shared")
    linked_clone  = optional(bool, true)
    auto_start    = optional(bool, true)
    cloud_init    = optional(bool, false)
    user_data     = optional(string, "")
    meta_data     = optional(string, "")
  }))
  default = {}
}

variable "pvm_vms" {
  description = "Map of VMs to create from PVM bundles"
  type = map(object({
    pvm_path     = string
    cpus         = optional(number, 2)
    memory       = optional(number, 4096)
    network_mode = optional(string, "shared")
    auto_start   = optional(bool, true)
    cloud_init   = optional(bool, false)
    user_data    = optional(string, "")
    meta_data    = optional(string, "")
  }))
  default = {}
}

variable "default_template_name" {
  description = "Default template to use if not specified per VM"
  type        = string
  default     = "ubuntu-minimal-test-template"
}

variable "enable_cloud_init" {
  description = "Enable cloud-init for all template VMs by default"
  type        = bool
  default     = true
}

variable "default_ssh_keys" {
  description = "List of SSH public keys to inject into VMs"
  type        = list(string)
  default     = []
}