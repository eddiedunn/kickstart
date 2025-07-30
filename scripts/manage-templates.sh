#!/bin/bash
#
# Template management utility for Parallels VMs
# Provides commands for managing VM templates
#

set -euo pipefail

# Configuration
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/Parallels/Templates}"
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
Template Management Utility for Parallels VMs

Usage: $0 <command> [options]

Commands:
  list                List all templates
  info <name>         Show template information
  convert <vm>        Convert VM to template
  revert <template>   Convert template back to VM
  export <template>   Export template as PVM
  import <pvm>        Import PVM as template
  delete <template>   Delete a template
  prepare <vm>        Prepare VM for templating
  clone <template>    Create VM from template

Examples:
  $0 list
  $0 prepare ubuntu-server
  $0 convert ubuntu-server
  $0 clone ubuntu-template --name web-01
  $0 export ubuntu-template

Environment:
  TEMPLATES_DIR   Directory for templates (default: ~/Parallels/Templates)
  EXPORT_DIR      Directory for exports (default: ./templates)
EOF
    exit 1
}

# List templates
cmd_list() {
    log_info "Templates:"
    echo
    prlctl list -a -t | grep -v "UUID" || echo "No templates found"
    
    if [ -d "$TEMPLATES_DIR" ]; then
        echo
        log_info "Template metadata files:"
        find "$TEMPLATES_DIR" -name "*.json" -type f | while read -r file; do
            echo "  - $(basename "$file")"
        done
    fi
}

# Show template info
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

# Convert VM to template
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
    
    # Create metadata
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

# Clone template to VM
cmd_clone() {
    local template_name="${1:-}"
    shift
    
    local vm_name=""
    local linked=false
    
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
        prlctl clone "$template_name" --name "$vm_name" --linked
    else
        prlctl clone "$template_name" --name "$vm_name"
    fi
    
    log_info "✓ VM '$vm_name' created from template"
    echo
    echo "Start with: prlctl start '$vm_name'"
}

# Main command dispatcher
case "${1:-}" in
    list)
        cmd_list
        ;;
    info)
        cmd_info "${2:-}"
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
    *)
        usage
        ;;
esac