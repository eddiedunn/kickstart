# Input Variables for ISO-based VM Deployments
#
# These variables control VM creation from Ubuntu autoinstall ISOs.
# For template-based deployments, see main-templates.tf

# VM Definitions - Primary configuration method
# Define multiple VMs with their specifications in terraform.tfvars
variable "vm_definitions" {
  description = "Map of VM definitions for multi-VM deployments. Each key becomes a VM instance."
  type = map(object({
    name        = string                      # VM name in Parallels (must be unique)
    cpus        = number                      # Number of CPU cores (1-32)
    memory      = number                      # RAM in MB (minimum 512)
    disk_size   = number                      # Disk size in GB (minimum 10)
    iso_path    = string                      # Path to autoinstall ISO
    network     = optional(string, "shared")  # Network type: shared, host, bridged
    start_after = optional(list(string), [])  # VM dependencies (not implemented)
  }))
  default = {}
  
  # Example usage in terraform.tfvars:
  # vm_definitions = {
  #   "web" = {
  #     name      = "ubuntu-web"
  #     cpus      = 2
  #     memory    = 4096
  #     disk_size = 30
  #     iso_path  = "../output/ubuntu-autoinstall.iso"
  #   }
  #   "db" = {
  #     name      = "ubuntu-db"
  #     cpus      = 4
  #     memory    = 8192
  #     disk_size = 50
  #     iso_path  = "../output/ubuntu-autoinstall.iso"
  #   }
  # }
}

# Default VM specifications
# Used when vm_definitions is empty (creates single default VM)

variable "default_cpus" {
  description = "Default number of CPU cores for VMs. Used when vm_definitions is empty."
  type        = number
  default     = 2
  
  validation {
    condition     = var.default_cpus >= 1 && var.default_cpus <= 32
    error_message = "CPU count must be between 1 and 32."
  }
}

variable "default_memory" {
  description = "Default memory in MB for VMs. Recommended minimum: 2048 (2GB)."
  type        = number
  default     = 4096  # 4GB
  
  validation {
    condition     = var.default_memory >= 512
    error_message = "Memory must be at least 512MB."
  }
}

variable "default_disk_size" {
  description = "Default disk size in GB for VMs. Disk is thin-provisioned (grows as needed)."
  type        = number
  default     = 30
  
  validation {
    condition     = var.default_disk_size >= 10
    error_message = "Disk size must be at least 10GB."
  }
}

variable "default_iso_path" {
  description = "Default path to Ubuntu autoinstall ISO. Create with build-autoinstall-iso.sh."
  type        = string
  default     = "../output/ubuntu-autoinstall.iso"
}

# SSH configuration
variable "ssh_public_key_path" {
  description = "Path to SSH public key file. If empty, auto-detects from ~/.ssh/ (id_ed25519.pub, id_rsa.pub, id_ecdsa.pub)."
  type        = string
  default     = ""
  
  # Leave empty for auto-detection, or specify path like:
  # ssh_public_key_path = "~/.ssh/custom_key.pub"
}

# Display configuration
variable "headless" {
  description = "Run VMs in headless mode (no GUI window). Set to false for desktop/debugging."
  type        = bool
  default     = true  # Headless by default for server deployments
}

# Advanced VM Features

variable "enable_nested_virt" {
  description = "Enable nested virtualization support. Allows running VMs inside VMs (e.g., Docker, KVM)."
  type        = bool
  default     = true  # Useful for development and containerization
}

variable "time_zone" {
  description = "Time zone for VMs. UTC recommended for servers to avoid DST issues."
  type        = string
  default     = "UTC"
  
  # Common values: "UTC", "America/New_York", "Europe/London", "Asia/Tokyo"
  # Full list: timedatectl list-timezones
}

# =============================================================================
# Template-based VM Deployment Variables
# These variables are used in main-templates.tf for template-based deployments
# =============================================================================

variable "template_vms" {
  description = "Map of VMs to create from Parallels templates. Used for fast, consistent deployments."
  type = map(object({
    template_name = string                    # Name of source template (required)
    cpus          = optional(number, 2)       # CPU cores to allocate
    memory        = optional(number, 4096)    # RAM in MB
    network_mode  = optional(string, "shared") # Network: shared, host, bridged
    linked_clone  = optional(bool, true)      # Use linked clone (saves space)
    auto_start    = optional(bool, true)      # Start VM after creation
    cloud_init    = optional(bool, false)     # Enable cloud-init customization
    user_data     = optional(string, "")      # Cloud-init user-data YAML
    meta_data     = optional(string, "")      # Cloud-init meta-data YAML
  }))
  default = {}
  
  # Example usage in terraform.tfvars:
  # template_vms = {
  #   "web-01" = {
  #     template_name = "ubuntu-base-template"
  #     cpus         = 2
  #     memory       = 2048
  #     cloud_init   = true
  #     user_data    = file("cloud-init/web-server.yaml")
  #   }
  # }
}

variable "pvm_vms" {
  description = "Map of VMs to create from exported PVM bundles. Used for deploying pre-configured VMs."
  type = map(object({
    pvm_path     = string                     # Path to .pvm file (required)
    cpus         = optional(number, 2)        # Override CPU allocation
    memory       = optional(number, 4096)     # Override RAM allocation
    network_mode = optional(string, "shared") # Network configuration
    auto_start   = optional(bool, true)       # Start after import
    cloud_init   = optional(bool, false)      # Apply cloud-init on first boot
    user_data    = optional(string, "")       # Cloud-init customization
    meta_data    = optional(string, "")       # Cloud-init metadata
  }))
  default = {}
  
  # Example usage:
  # pvm_vms = {
  #   "imported-vm" = {
  #     pvm_path = "./templates/ubuntu-base.pvm"
  #     memory   = 8192
  #   }
  # }
}

# Template defaults

variable "default_template_name" {
  description = "Default template name to use if not specified per VM. Must exist in Parallels."
  type        = string
  default     = "ubuntu-minimal-test-template"
  
  # Create templates with: ./scripts/manage-templates.sh create <vm-name>
}

variable "enable_cloud_init" {
  description = "Enable cloud-init for all template-based VMs by default. Allows post-deployment customization."
  type        = bool
  default     = true
}

variable "default_ssh_keys" {
  description = "List of SSH public keys to inject into all VMs. Used when cloud-init is enabled."
  type        = list(string)
  default     = []
  
  # Example:
  # default_ssh_keys = [
  #   "ssh-ed25519 AAAAC3... user@host",
  #   file("~/.ssh/id_rsa.pub")
  # ]
}