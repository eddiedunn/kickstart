variable "vm_name" {
  description = "Name for the VM"
  type        = string
}

# Source options (one of these should be specified)
variable "template_name" {
  description = "Name of the Parallels template to clone from"
  type        = string
  default     = ""
}

variable "pvm_path" {
  description = "Path to PVM bundle to import"
  type        = string
  default     = ""
}

variable "snapshot_id" {
  description = "Snapshot ID to restore from"
  type        = string
  default     = ""
}

variable "source_vm" {
  description = "Source VM name (required when using snapshot_id)"
  type        = string
  default     = ""
}

# Hardware customization
variable "cpus" {
  description = "Number of CPUs (0 = use template default)"
  type        = number
  default     = 0
}

variable "memory" {
  description = "Memory in MB (0 = use template default)"
  type        = number
  default     = 0
}

# Network configuration
variable "network_mode" {
  description = "Network mode: shared, bridged, host-only"
  type        = string
  default     = "shared"
}

# Clone options
variable "linked_clone" {
  description = "Create linked clone (saves disk space)"
  type        = bool
  default     = true
}

# Startup options
variable "auto_start" {
  description = "Automatically start the VM after creation"
  type        = bool
  default     = true
}

# Cloud-init configuration
variable "cloud_init" {
  description = "Enable cloud-init customization"
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Cloud-init user-data content"
  type        = string
  default     = ""
}

variable "meta_data" {
  description = "Cloud-init meta-data content"
  type        = string
  default     = ""
}