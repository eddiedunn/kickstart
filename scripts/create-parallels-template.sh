#!/bin/bash
#
# Create Parallels VM template from prepared VM
# Supports multiple export formats
#

set -euo pipefail

# Configuration
VM_NAME="${1:-}"
MODE="${2:-template}"  # template, export, snapshot
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

# Ensure VM is stopped
VM_STATUS=$(prlctl list -i "$VM_NAME" | grep "State:" | awk '{print $2}')
if [ "$VM_STATUS" != "stopped" ]; then
    log_warn "VM is $VM_STATUS, stopping..."
    prlctl stop "$VM_NAME" --kill 2>/dev/null || true
    sleep 5
fi

# Get VM info
VM_UUID=$(prlctl list -i "$VM_NAME" | grep "UUID:" | awk '{print $2}')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

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
        
        # Clone and convert to template
        prlctl clone "$VM_NAME" --name "$TEMPLATE_NAME" --template
        
        # Move to templates location
        VM_HOME=$(prlctl list -i "$TEMPLATE_NAME" --json | jq -r '.[0].Home')
        if [ -n "$VM_HOME" ] && [ "$VM_HOME" != "$TEMPLATES_DIR" ]; then
            log_info "Moving template to $TEMPLATES_DIR..."
            mv "$VM_HOME" "$TEMPLATES_DIR/" 2>/dev/null || true
        fi
        
        # Get template UUID
        TEMPLATE_UUID=$(prlctl list -i "$TEMPLATE_NAME" | grep "UUID:" | awk '{print $2}')
        
        log_info "✓ Template created: $TEMPLATE_NAME (UUID: $TEMPLATE_UUID)"
        
        # Create metadata file
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
        ;&  # Fall through if mode is "all"
    
    export|all)
        log_step "Exporting VM as portable PVM bundle..."
        
        # Create export directory
        mkdir -p "$EXPORT_DIR"
        
        # Export VM
        EXPORT_NAME="${VM_NAME}-${TIMESTAMP}.pvm"
        EXPORT_PATH="${EXPORT_DIR}/${EXPORT_NAME}"
        
        log_info "Exporting to $EXPORT_PATH..."
        prlctl export "$VM_NAME" -o "$EXPORT_PATH"
        
        # Create checksum
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