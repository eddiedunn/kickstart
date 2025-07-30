variable "vm_definitions" {
  description = "Map of VM definitions for multi-VM deployments"
  type = map(object({
    name        = string
    cpus        = number
    memory      = number
    disk_size   = number
    iso_path    = string
    network     = optional(string, "shared")
    start_after = optional(list(string), [])
  }))
  default = {}
}

variable "default_cpus" {
  description = "Default number of CPUs for VMs"
  type        = number
  default     = 2
}

variable "default_memory" {
  description = "Default memory in MB for VMs"
  type        = number
  default     = 4096
}

variable "default_disk_size" {
  description = "Default disk size in GB for VMs"
  type        = number
  default     = 30
}

variable "default_iso_path" {
  description = "Default path to autoinstall ISO"
  type        = string
  default     = "../output/ubuntu-autoinstall.iso"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file (auto-detected if not specified)"
  type        = string
  default     = ""
}

variable "headless" {
  description = "Run VMs in headless mode (no GUI)"
  type        = bool
  default     = true
}

variable "enable_nested_virt" {
  description = "Enable nested virtualization"
  type        = bool
  default     = true
}

variable "time_zone" {
  description = "Time zone for VMs"
  type        = string
  default     = "UTC"
}