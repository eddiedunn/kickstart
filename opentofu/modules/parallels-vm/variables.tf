variable "name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "template_uuid" {
  description = "UUID of the Parallels template to clone from"
  type        = string
  default     = ""
}

variable "template_name" {
  description = "Name of the Parallels template to clone from"
  type        = string
  default     = ""
}

variable "pvm_bundle_path" {
  description = "Path to PVM bundle file to import"
  type        = string
  default     = ""
}

variable "iso_path" {
  description = "Path to ISO file for new VM installation"
  type        = string
  default     = ""
}

variable "linked_clone" {
  description = "Create a linked clone (uses less disk space)"
  type        = bool
  default     = true
}

variable "cpus" {
  description = "Number of CPUs"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory size in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Disk size in GB (only for ISO deployments)"
  type        = number
  default     = 20
}

variable "headless" {
  description = "Run VM in headless mode"
  type        = bool
  default     = false
}

variable "cloud_init_config" {
  description = "Cloud-init user-data configuration (YAML format)"
  type        = string
  default     = ""
}

variable "network_mode" {
  description = "Network mode: shared, host, or bridged"
  type        = string
  default     = "shared"
}