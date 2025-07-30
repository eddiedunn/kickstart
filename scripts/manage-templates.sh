#!/bin/bash
#
# manage-templates.sh - Comprehensive VM Template Management for Parallels Desktop
#
# PURPOSE:
#   Provides a complete toolkit for creating, managing, and deploying VM templates
#   in Parallels Desktop. Supports linked clones, PVM exports, and template updates.
#   This is your central command for all template-related operations.
#
# USAGE:
#   ./manage-templates.sh <command> [options]
#
# COMMANDS:
#   list                List all templates with metadata
#   info <name>         Show detailed template information
#   create <vm>         Create template from VM (prepare + convert)
#   update <template>   Update template with latest OS patches
#   convert <vm>        Convert VM to template (without preparation)
#   revert <template>   Convert template back to regular VM
#   export <template>   Export template as portable PVM bundle
#   import <pvm>        Import PVM file as template
#   delete <template>   Permanently delete a template
#   prepare <vm>        Prepare VM for templating (generalize)
#   clone <template>    Create new VM from template
#   setup <vm>          Setup VM with tools and updates
#
# KEY FEATURES:
#   - Create templates from existing VMs with proper generalization
#   - Clone templates to new VMs using linked clones (saves space)
#   - Export/import templates as portable PVM bundles for sharing
#   - Update templates with latest security patches
#   - Prepare VMs by removing machine-specific data
#   - Track template metadata and creation history
#   - Automated or manual VM setup options
#
# TEMPLATE TYPES:
#   1. Linked Clone Templates:
#      - Shares base disk with clones (space-efficient)
#      - Fastest deployment method
#      - Best for local development/testing
#      - Cannot be moved to different hosts
#   
#   2. PVM Bundle Exports:
#      - Self-contained, portable VM packages
#      - Can be shared between Parallels hosts
#      - Larger size but completely independent
#      - Best for distribution and archival
#   
#   3. Snapshots:
#      - Point-in-time VM state captures
#      - Easy rollback capability
#      - Good for testing configurations
#      - Not true templates but useful for versioning
#
# PREREQUISITES:
#   - Parallels Desktop Pro/Business installed and licensed
#   - jq for JSON processing: brew install jq (macOS)
#   - Sufficient disk space (linked clones: minimal, PVM: full VM size)
#   - SSH access to VMs for updates and setup
#
# ENVIRONMENT VARIABLES:
#   TEMPLATES_DIR   - Storage for template metadata (default: ~/Parallels/Templates)
#   EXPORT_DIR      - Storage for PVM exports (default: ./templates)
#

set -euo pipefail

# Configuration
# Templates stored in user's Parallels directory by default
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/Parallels/Templates}"
# PVM exports go to project templates directory
EXPORT_DIR="${EXPORT_DIR:-./templates}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

usage() {
    cat << EOF
$(echo -e "${GREEN}Template Management Utility for Parallels VMs${NC}")
$(echo -e "${GREEN}============================================${NC}")

Usage: $0 <command> [options]

COMMANDS:
  ${BLUE}list${NC}                List all templates with status and metadata
  ${BLUE}info${NC} <name>         Show detailed template information and history
  ${BLUE}create${NC} <vm>         Create new template from VM (recommended method)
                      Runs prepare + convert in sequence
  ${BLUE}update${NC} <template>   Update template with latest OS patches and security fixes
                      Creates temporary clone, updates, replaces original
  ${BLUE}convert${NC} <vm>        Convert existing VM to template format
                      VM becomes read-only, optimized for cloning
  ${BLUE}revert${NC} <template>   Convert template back to regular VM
                      Allows modifications, loses template benefits
  ${BLUE}export${NC} <template>   Export template as portable PVM bundle
                      Creates timestamped archive with checksum
  ${BLUE}import${NC} <pvm>        Import PVM bundle as new template
                      Registers and converts to template format
  ${BLUE}delete${NC} <template>   Permanently delete template and metadata
                      Requires confirmation unless --force used
  ${BLUE}prepare${NC} <vm>        Prepare VM for templating (generalization)
                      Removes SSH keys, logs, machine IDs
  ${BLUE}clone${NC} <template>    Create new VM from template
    Options:
      --name <name>     Set VM name (default: auto-generated)
      --linked          Create linked clone (default: full clone)
  ${BLUE}setup${NC} <vm>          Setup VM with essential tools and updates
    Options:
      --manual          Show commands instead of executing

EXAMPLES:
  # List all available templates
  $0 list
  
  # Create a new template from existing VM
  $0 create ubuntu-server
  
  # Quick deployment from template
  $0 clone ubuntu-template --name web-01 --linked
  
  # Export template for backup or sharing
  $0 export ubuntu-template
  
  # Update template with latest patches
  $0 update ubuntu-template
  
  # Manual VM setup (shows commands)
  $0 setup my-vm --manual

WORKFLOW EXAMPLE:
  1. Deploy VM: ./deploy-vm.sh output/ubuntu.iso my-vm
  2. Configure VM as needed (install software, settings)
  3. Create template: $0 create my-vm
  4. Deploy clones: $0 clone my-vm-template --name app-01 --linked

ENVIRONMENT VARIABLES:
  TEMPLATES_DIR   Template metadata storage (default: ~/Parallels/Templates)
  EXPORT_DIR      PVM export location (default: ./templates)

TEMPLATE BEST PRACTICES:
  - Always run 'prepare' before creating templates
  - Use linked clones for development (space-efficient)
  - Export templates before major updates
  - Update templates monthly for security patches
  - Document template contents in metadata

For more information, see docs/VM-TEMPLATE-GUIDE.md
EOF
    exit 1
}

# List all available templates
# Shows both Parallels templates and metadata files
cmd_list() {
    log_info "Templates:"
    echo
    # List Parallels templates (-t flag shows templates only)
    prlctl list -a -t | grep -v "UUID" || echo "No templates found"
    
    if [ -d "$TEMPLATES_DIR" ]; then
        echo
        log_info "Template metadata files:"
        find "$TEMPLATES_DIR" -name "*.json" -type f | while read -r file; do
            echo "  - $(basename "$file")"
        done
    fi
}

# Show detailed information about a specific template
# Displays VM configuration and metadata if available
cmd_info() {
    local template_name="${1:-}"
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    log_info "Template information for '$template_name':"
    prlctl list -i "$template_name"
    
    # Show metadata if exists
    if [ -f "$TEMPLATES_DIR/${template_name}.json" ]; then
        echo
        log_info "Metadata:"
        cat "$TEMPLATES_DIR/${template_name}.json"
    fi
}

# Convert an existing VM to a template
# This makes the VM read-only and optimizes it for cloning
cmd_convert() {
    local vm_name="${1:-}"
    if [ -z "$vm_name" ]; then
        log_error "VM name required"
        usage
    fi
    
    if ! prlctl list -a | grep -q "$vm_name"; then
        log_error "VM '$vm_name' not found"
        exit 1
    fi
    
    if prlctl list -a -t | grep -q "$vm_name"; then
        log_warn "Already a template"
        exit 0
    fi
    
    log_info "Converting VM '$vm_name' to template..."
    prlctl set "$vm_name" --template on
    
    # Create metadata file to track template information
    # This helps with template management and versioning
    mkdir -p "$TEMPLATES_DIR"
    UUID=$(prlctl list -i "$vm_name" | grep "UUID:" | awk '{print $2}')
    cat > "$TEMPLATES_DIR/${vm_name}.json" << EOF
{
  "name": "$vm_name",
  "uuid": "$UUID",
  "converted": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "template"
}
EOF
    
    log_info "✓ VM converted to template"
}

# Revert template to VM
cmd_revert() {
    local template_name="${1:-}"
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    log_info "Converting template '$template_name' back to VM..."
    prlctl set "$template_name" --template off
    
    # Remove metadata
    rm -f "$TEMPLATES_DIR/${template_name}.json"
    
    log_info "✓ Template converted to VM"
}

# Export template
cmd_export() {
    local template_name="${1:-}"
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    mkdir -p "$EXPORT_DIR"
    local export_path="$EXPORT_DIR/${template_name}-$(date +%Y%m%d-%H%M%S).pvm"
    
    log_info "Exporting template to '$export_path'..."
    prlctl export "$template_name" -o "$export_path"
    
    # Create checksum
    (cd "$EXPORT_DIR" && shasum -a 256 "$(basename "$export_path")" > "$(basename "$export_path").sha256")
    
    log_info "✓ Template exported"
    echo "Path: $export_path"
    echo "Size: $(du -h "$export_path" | cut -f1)"
}

# Import PVM as template
cmd_import() {
    local pvm_path="${1:-}"
    if [ -z "$pvm_path" ] || [ ! -f "$pvm_path" ]; then
        log_error "Valid PVM file path required"
        usage
    fi
    
    log_info "Importing PVM as template..."
    
    # Register PVM
    prlctl register "$pvm_path" --regenerate-src-uuid
    
    # Get VM name
    local vm_name=$(basename "$pvm_path" .pvm)
    
    # Convert to template
    prlctl set "$vm_name" --template on
    
    log_info "✓ PVM imported as template '$vm_name'"
}

# Delete template
cmd_delete() {
    local template_name="${1:-}"
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    log_warn "This will permanently delete template '$template_name'"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting template..."
        prlctl delete "$template_name"
        rm -f "$TEMPLATES_DIR/${template_name}.json"
        log_info "✓ Template deleted"
    else
        log_info "Deletion cancelled"
    fi
}

# Prepare VM for templating
cmd_prepare() {
    local vm_name="${1:-}"
    if [ -z "$vm_name" ]; then
        log_error "VM name required"
        usage
    fi
    
    # Call the prepare script
    if [ -x "$(dirname "$0")/prepare-vm-template.sh" ]; then
        "$(dirname "$0")/prepare-vm-template.sh" "$vm_name"
    else
        log_error "prepare-vm-template.sh not found"
        exit 1
    fi
}

# Clone a template to create a new VM
# Supports both linked clones (space-efficient) and full clones
cmd_clone() {
    local template_name="${1:-}"
    shift
    
    local vm_name=""
    local linked=false  # Default to full clone for portability
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                vm_name="$2"
                shift 2
                ;;
            --linked)
                linked=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if [ -z "$vm_name" ]; then
        vm_name="${template_name}-clone-$(date +%Y%m%d-%H%M%S)"
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    log_info "Cloning template '$template_name' to VM '$vm_name'..."
    
    if [ "$linked" = true ]; then
        # Linked clone - shares base disk with template (fast, space-efficient)
        prlctl clone "$template_name" --name "$vm_name" --linked
    else
        # Full clone - completely independent copy
        prlctl clone "$template_name" --name "$vm_name"
    fi
    
    log_info "✓ VM '$vm_name' created from template"
    echo
    echo "Start with: prlctl start '$vm_name'"
}

# Create a new template from a VM (combines prepare + convert)
# This is the recommended way to create templates
cmd_create() {
    local vm_name="${1:-}"
    if [ -z "$vm_name" ]; then
        log_error "VM name required"
        usage
    fi
    
    log_info "Creating template from VM '$vm_name'..."
    
    # First prepare the VM
    cmd_prepare "$vm_name"
    
    # Then convert to template
    cmd_convert "$vm_name"
    
    log_info "✓ Template created successfully"
}

# Update an existing template with latest OS patches
# Creates temporary VM, applies updates, then replaces template
cmd_update() {
    local template_name="${1:-}"
    if [ -z "$template_name" ]; then
        log_error "Template name required"
        usage
    fi
    
    if ! prlctl list -a -t | grep -q "$template_name"; then
        log_error "Template '$template_name' not found"
        exit 1
    fi
    
    log_info "Updating template '$template_name'..."
    
    # Create temporary VM from template
    local temp_vm="${template_name}-update-$(date +%s)"
    log_step "Creating temporary VM..."
    prlctl clone "$template_name" --name "$temp_vm"
    
    # Start VM and wait for it
    log_step "Starting VM..."
    prlctl start "$temp_vm"
    sleep 30
    
    # Get VM IP
    local vm_ip
    vm_ip=$(prlctl list -f --json | jq -r ".[] | select(.name==\"$temp_vm\") | .ip_configured")
    
    if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
        log_error "Could not get VM IP address"
        prlctl delete "$temp_vm"
        exit 1
    fi
    
    log_step "Running updates on VM (IP: $vm_ip)..."
    # Update package lists and upgrade all packages
    prlctl exec "$temp_vm" "sudo apt update && sudo apt upgrade -y"
    # Clean up package cache to reduce template size
    prlctl exec "$temp_vm" "sudo apt autoremove -y && sudo apt clean"
    
    # Stop and prepare VM
    log_step "Preparing VM for template..."
    prlctl stop "$temp_vm"
    cmd_prepare "$temp_vm"
    
    # Delete old template and rename new one
    log_step "Replacing template..."
    prlctl delete "$template_name"
    prlctl set "$temp_vm" --name "$template_name"
    prlctl set "$template_name" --template on
    
    log_info "✓ Template '$template_name' updated successfully"
}

# Setup a VM with essential tools and configurations
# Can run automated or display manual commands
cmd_setup() {
    local vm_name="${1:-}"
    local manual=false  # Show commands vs execute them
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --manual)
                manual=true
                shift
                ;;
            *)
                vm_name="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "$vm_name" ]; then
        log_error "VM name required"
        usage
    fi
    
    if [ "$manual" = true ]; then
        # Print manual commands
        # Display manual setup commands for user to run
        cat << EOF
================================================================================
Manual VM Setup Commands for '$vm_name'
================================================================================

1. Get VM IP address:
   prlctl list -f --json | jq -r '.[] | select(.name=="$vm_name") | .ip_configured'

2. SSH into the VM:
   ssh ubuntu@<VM_IP>

3. Run these commands:

# Update system packages
sudo apt update && sudo apt upgrade -y

# Configure sudo NOPASSWD
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ubuntu

# Install essential packages
sudo apt install -y curl wget git htop net-tools build-essential

# Prepare for Parallels Tools
sudo apt install -y linux-headers-\$(uname -r) dkms

# Install Parallels Tools (from Parallels Desktop menu: Actions > Install Parallels Tools)
# Then mount and install:
sudo mount /dev/cdrom /mnt
sudo /mnt/install

# Clean up
sudo apt autoremove -y
sudo apt clean

================================================================================
EOF
    else
        # Automated setup
        if ! prlctl list -a | grep -q "$vm_name"; then
            log_error "VM '$vm_name' not found"
            exit 1
        fi
        
        # Get VM IP
        local vm_ip
        vm_ip=$(prlctl list -f --json | jq -r ".[] | select(.name==\"$vm_name\") | .ip_configured")
        
        if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
            log_error "Could not get VM IP address. Is the VM running?"
            exit 1
        fi
        
        log_info "Setting up VM '$vm_name' (IP: $vm_ip)..."
        
        # Run setup commands
        prlctl exec "$vm_name" "sudo apt update && sudo apt upgrade -y"
        prlctl exec "$vm_name" "echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ubuntu"
        prlctl exec "$vm_name" "sudo apt install -y curl wget git htop net-tools build-essential"
        prlctl exec "$vm_name" "sudo apt install -y linux-headers-\$(uname -r) dkms"
        prlctl exec "$vm_name" "sudo apt autoremove -y && sudo apt clean"
        
        log_info "✓ VM setup completed"
        log_warn "Remember to install Parallels Tools from the Parallels Desktop menu"
    fi
}

# Main command dispatcher
# Routes commands to appropriate handler functions
case "${1:-}" in
    list)
        cmd_list
        ;;
    info)
        cmd_info "${2:-}"
        ;;
    create)
        cmd_create "${2:-}"
        ;;
    update)
        cmd_update "${2:-}"
        ;;
    convert)
        cmd_convert "${2:-}"
        ;;
    revert)
        cmd_revert "${2:-}"
        ;;
    export)
        cmd_export "${2:-}"
        ;;
    import)
        cmd_import "${2:-}"
        ;;
    delete)
        cmd_delete "${2:-}"
        ;;
    prepare)
        cmd_prepare "${2:-}"
        ;;
    clone)
        shift
        cmd_clone "$@"
        ;;
    setup)
        shift
        cmd_setup "$@"
        ;;
    *)
        usage
        ;;
esac