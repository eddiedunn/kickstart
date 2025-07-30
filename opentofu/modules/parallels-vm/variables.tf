# Variables for the parallels-vm module
# This module supports multiple VM creation methods:
# 1. From ISO (new installation)
# 2. From template (clone existing)
# 3. From PVM bundle (import and register)

variable "name" {
  description = "Name of the virtual machine in Parallels Desktop. Must be unique."
  type        = string
  
  validation {
    condition     = length(var.name) > 0
    error_message = "VM name cannot be empty."
  }
}

# Template-based deployment variables
variable "template_uuid" {
  description = "UUID of the Parallels template to clone from. Use 'prlctl list -t' to find UUIDs."
  type        = string
  default     = ""
}

variable "template_name" {
  description = "Name of the Parallels template to clone from. Alternative to template_uuid."
  type        = string
  default     = ""
}

variable "pvm_bundle_path" {
  description = "Path to PVM bundle file to import. Must be a valid .pvm file exported from Parallels."
  type        = string
  default     = ""
}

# ISO-based deployment variable
variable "iso_path" {
  description = "Path to ISO file for new VM installation. Should be an autoinstall ISO for unattended setup."
  type        = string
  default     = ""
}

# Clone configuration
variable "linked_clone" {
  description = "Create a linked clone (shares base disk with template). Saves disk space but requires template to remain."
  type        = bool
  default     = true
}

# Hardware configuration
variable "cpus" {
  description = "Number of virtual CPU cores to allocate. Recommended: 2-4 for general use."
  type        = number
  default     = 2
  
  validation {
    condition     = var.cpus >= 1 && var.cpus <= 32
    error_message = "CPUs must be between 1 and 32."
  }
}

variable "memory" {
  description = "Memory size in MB. Recommended: 2048 (2GB) minimum, 4096 (4GB) for better performance."
  type        = number
  default     = 2048
  
  validation {
    condition     = var.memory >= 512 && var.memory <= 524288
    error_message = "Memory must be between 512MB and 512GB."
  }
}

variable "disk_size" {
  description = "Disk size in GB (only used for ISO deployments). Disk is thin-provisioned (grows as needed)."
  type        = number
  default     = 20
  
  validation {
    condition     = var.disk_size >= 10
    error_message = "Disk size must be at least 10GB."
  }
}

# Display configuration
variable "headless" {
  description = "Run VM in headless mode (no GUI window). Useful for server deployments."
  type        = bool
  default     = false
}

# Cloud-init configuration
variable "cloud_init_config" {
  description = "Cloud-init user-data configuration in YAML format. Applied on first boot for customization."
  type        = string
  default     = ""
}

# Network configuration
variable "network_mode" {
  description = "Network mode: 'shared' (NAT), 'host' (host-only), or 'bridged' (direct network access)."
  type        = string
  default     = "shared"
  
  validation {
    condition     = contains(["shared", "host", "bridged"], var.network_mode)
    error_message = "Network mode must be 'shared', 'host', or 'bridged'."
  }
}