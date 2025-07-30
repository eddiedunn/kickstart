#!/bin/bash
#
# create-parallels-template.sh - Create VM Templates in Multiple Formats
#
# PURPOSE:
#   Converts a prepared VM into various template formats for different use cases.
#   Supports linked-clone templates, portable PVM bundles, and snapshots.
#   Each format serves different deployment and distribution needs.
#
# USAGE:
#   ./create-parallels-template.sh <vm-name> [mode]
#
# PARAMETERS:
#   $1 - VM name to convert (required)
#        Must be an existing VM in Parallels Desktop
#        Should be prepared with prepare-vm-template.sh first
#   
#   $2 - Template mode (optional):
#        - template: Create linked-clone template (default)
#        - export:   Create portable PVM bundle
#        - snapshot: Create VM snapshot for versioning
#        - all:      Create all three formats
#
# TEMPLATE FORMATS EXPLAINED:
#
#   1. Linked-Clone Template (mode: template):
#      - Creates a read-only base template
#      - Clones share disk blocks with template (copy-on-write)
#      - Deployment time: 10-30 seconds
#      - Disk usage: ~100MB per clone
#      - Use case: Rapid local development/testing
#      - Limitation: Cannot move to other hosts
#   
#   2. PVM Bundle Export (mode: export):
#      - Packages VM into portable .pvm file
#      - Includes all VM data and configuration
#      - File size: Full VM size (compressed)
#      - Use case: Template distribution, archival
#      - Benefit: Works across different Parallels hosts
#   
#   3. Snapshot (mode: snapshot):
#      - Creates point-in-time VM state capture
#      - Allows quick rollback to this state
#      - Storage: Incremental (only changes)
#      - Use case: Version control, testing
#      - Note: Not a true template, but useful
#
# EXAMPLES:
#   # Create linked-clone template only
#   ./create-parallels-template.sh ubuntu-server
#   
#   # Export VM as portable PVM bundle
#   ./create-parallels-template.sh ubuntu-server export
#   
#   # Create all template formats
#   ./create-parallels-template.sh ubuntu-server all
#   
#   # After creating template, deploy clones:
#   prlctl clone ubuntu-server-template --name web-01 --linked
#
# WORKFLOW:
#   1. Validates VM exists and is stopped
#   2. Creates specified template format(s)
#   3. Generates metadata for tracking
#   4. Provides deployment commands
#
# OUTPUT LOCATIONS:
#   - Templates: ~/Parallels/ (Parallels default)
#   - Metadata: $TEMPLATES_DIR/<name>.json
#   - PVM exports: $EXPORT_DIR/<name>-<timestamp>.pvm
#   - Checksums: $EXPORT_DIR/<name>-<timestamp>.pvm.sha256
#
# PREREQUISITES:
#   - VM must be stopped (script will stop if running)
#   - VM should be prepared (generalized) first
#   - Disk space requirements:
#     * Template mode: Minimal (~100MB)
#     * Export mode: Full VM size
#     * Snapshot mode: Variable (changes only)
#
# BEST PRACTICES:
#   1. Always prepare VMs before templating
#   2. Use descriptive template names
#   3. Document template contents in metadata
#   4. Export templates before major changes
#   5. Test templates with a clone before use
#
# ENVIRONMENT VARIABLES:
#   TEMPLATES_DIR - Metadata storage (default: ~/Parallels/Templates)
#   EXPORT_DIR    - PVM export location (default: ./templates)
#
# SEE ALSO:
#   - prepare-vm-template.sh: Prepare VMs for templating
#   - manage-templates.sh: Complete template management
#   - OpenTofu modules: Automated template deployment
#

set -euo pipefail

# Configuration
VM_NAME="${1:-}"                                           # VM to convert
MODE="${2:-template}"                                      # Default to template mode
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/Parallels/Templates}" # Template storage
EXPORT_DIR="${EXPORT_DIR:-./templates}"                    # PVM export directory

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
Usage: $0 <vm-name> [mode]

Modes:
  template  - Convert to linked-clone template (default)
  export    - Export as portable PVM bundle
  snapshot  - Create a snapshot for versioning
  all       - Do all of the above

Examples:
  $0 ubuntu-minimal-test                    # Create template
  $0 ubuntu-minimal-test export             # Export PVM
  $0 ubuntu-minimal-test all                # All methods

Environment variables:
  TEMPLATES_DIR - Directory for templates (default: ~/Parallels/Templates)
  EXPORT_DIR    - Directory for PVM exports (default: ./templates)
EOF
    exit 1
}

# Check arguments
if [ -z "$VM_NAME" ]; then
    usage
fi

# Check if VM exists
if ! prlctl list -a | grep -q "$VM_NAME"; then
    log_error "VM '$VM_NAME' not found"
    exit 1
fi

# Ensure VM is stopped before template operations
# Templates must be created from stopped VMs to ensure consistency
VM_STATUS=$(prlctl list -i "$VM_NAME" | grep "State:" | awk '{print $2}')
if [ "$VM_STATUS" != "stopped" ]; then
    log_warn "VM is $VM_STATUS, stopping..."
    prlctl stop "$VM_NAME" --kill 2>/dev/null || true
    sleep 5
fi

# Get VM info
VM_UUID=$(prlctl list -i "$VM_NAME" | grep "UUID:" | awk '{print $2}')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Process based on selected mode
case "$MODE" in
    template|all)
        log_step "Creating linked-clone template from '$VM_NAME'..."
        
        # Create templates directory
        mkdir -p "$TEMPLATES_DIR"
        
        # Clone VM as template
        TEMPLATE_NAME="${VM_NAME}-template"
        log_info "Creating template '$TEMPLATE_NAME'..."
        
        # Remove existing template if exists
        if prlctl list -a -t | grep -q "$TEMPLATE_NAME"; then
            log_warn "Removing existing template..."
            prlctl delete "$TEMPLATE_NAME"
        fi
        
        # Clone VM and convert to template in one operation
        # The --template flag makes it a template immediately
        prlctl clone "$VM_NAME" --name "$TEMPLATE_NAME" --template
        
        # Move template to designated templates directory
        # This keeps templates organized and separate from regular VMs
        VM_HOME=$(prlctl list -i "$TEMPLATE_NAME" --json | jq -r '.[0].Home')
        if [ -n "$VM_HOME" ] && [ "$VM_HOME" != "$TEMPLATES_DIR" ]; then
            log_info "Moving template to $TEMPLATES_DIR..."
            mv "$VM_HOME" "$TEMPLATES_DIR/" 2>/dev/null || true
        fi
        
        # Get template UUID
        TEMPLATE_UUID=$(prlctl list -i "$TEMPLATE_NAME" | grep "UUID:" | awk '{print $2}')
        
        log_info "✓ Template created: $TEMPLATE_NAME (UUID: $TEMPLATE_UUID)"
        
        # Create metadata file for template tracking
        # Stores creation info and source VM details
        cat > "$TEMPLATES_DIR/${TEMPLATE_NAME}.json" << EOF
{
  "name": "$TEMPLATE_NAME",
  "uuid": "$TEMPLATE_UUID",
  "source_vm": "$VM_NAME",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "linked-clone-template"
}
EOF
        
        if [ "$MODE" != "all" ]; then
            echo
            echo "To deploy VMs from this template, use:"
            echo "  tofu apply -var=\"template_name=$TEMPLATE_NAME\""
        fi
        ;&  # Fall through to next case if mode is "all"
    
    export|all)
        log_step "Exporting VM as portable PVM bundle..."
        
        # Create export directory
        mkdir -p "$EXPORT_DIR"
        
        # Define export file name with timestamp
        # Timestamps prevent overwriting previous exports
        EXPORT_NAME="${VM_NAME}-${TIMESTAMP}.pvm"
        EXPORT_PATH="${EXPORT_DIR}/${EXPORT_NAME}"
        
        log_info "Exporting to $EXPORT_PATH..."
        prlctl export "$VM_NAME" -o "$EXPORT_PATH"
        
        # Create SHA-256 checksum for integrity verification
        # Important for ensuring PVM hasn't been corrupted during transfer
        log_info "Creating checksum..."
        (cd "$EXPORT_DIR" && shasum -a 256 "$EXPORT_NAME" > "${EXPORT_NAME}.sha256")
        
        # Create metadata
        cat > "${EXPORT_PATH}.json" << EOF
{
  "name": "$VM_NAME",
  "uuid": "$VM_UUID",
  "exported": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "size": "$(du -h "$EXPORT_PATH" | cut -f1)",
  "checksum": "$(cat "${EXPORT_PATH}.sha256" | awk '{print $1}')",
  "type": "pvm-bundle"
}
EOF
        
        log_info "✓ PVM bundle exported: $EXPORT_PATH"
        
        if [ "$MODE" != "all" ]; then
            echo
            echo "To import and deploy:"
            echo "  prlctl register \"$EXPORT_PATH\""
            echo "  tofu apply -var=\"pvm_path=$EXPORT_PATH\""
        fi
        ;&  # Fall through if mode is "all"
    
    snapshot|all)
        log_step "Creating snapshot for versioning..."
        
        # Create descriptive snapshot name and description
        SNAPSHOT_NAME="template-${TIMESTAMP}"
        SNAPSHOT_DESC="Template snapshot created on $(date)"
        
        log_info "Creating snapshot '$SNAPSHOT_NAME'..."
        prlctl snapshot "$VM_NAME" --name "$SNAPSHOT_NAME" --description "$SNAPSHOT_DESC"
        
        # List snapshots
        log_info "Current snapshots:"
        prlctl snapshot-list "$VM_NAME"
        
        log_info "✓ Snapshot created: $SNAPSHOT_NAME"
        
        if [ "$MODE" != "all" ]; then
            echo
            echo "To revert to this snapshot:"
            echo "  prlctl snapshot-switch \"$VM_NAME\" --id \"$SNAPSHOT_NAME\""
        fi
        ;;
    
    *)
        log_error "Unknown mode: $MODE"
        usage
        ;;
esac

# Provide comprehensive summary when all formats are created
if [ "$MODE" = "all" ]; then
    echo
    log_info "✓ All template formats created successfully!"
    echo
    echo "Summary:"
    echo "  - Linked-clone template: $TEMPLATE_NAME"
    echo "  - PVM bundle: $EXPORT_PATH"
    echo "  - Snapshot: $SNAPSHOT_NAME"
    echo
    echo "Deployment options:"
    echo "  1. Fast local deployment: tofu apply -var=\"template_name=$TEMPLATE_NAME\""
    echo "  2. Portable deployment: tofu apply -var=\"pvm_path=$EXPORT_PATH\""
    echo "  3. Snapshot restore: prlctl snapshot-switch \"$VM_NAME\" --id \"$SNAPSHOT_NAME\""
fi