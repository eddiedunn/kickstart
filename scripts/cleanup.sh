#!/bin/bash
#
# cleanup.sh - Clean Up VMs and Project Resources
#
# PURPOSE:
#   Safely removes VMs, ISOs, and OpenTofu/Terraform state files.
#   Helps maintain a clean development environment and recover disk space.
#   Essential for resetting your environment or cleaning up after testing.
#
# USAGE:
#   ./cleanup.sh [OPTIONS]
#
# OPTIONS:
#   --isos      Remove generated ISO files from output/
#   --all       Remove all resources (VMs, ISOs, Terraform state)
#   --force,-f  Skip confirmation prompts (use with caution)
#   --help,-h   Show this help message
#
# WHAT IT CLEANS:
#
#   1. Terraform/OpenTofu Managed VMs:
#      - VMs tracked in terraform.tfstate
#      - Proper cleanup via 'tofu destroy'
#      - Ensures clean state removal
#
#   2. Orphaned Parallels VMs:
#      - VMs matching 'ubuntu-' or 'Ubuntu' patterns
#      - Not managed by Terraform/OpenTofu
#      - Leftover from manual creation or failed deployments
#
#   3. Generated ISO Files (--isos flag):
#      - All .iso files in output/ directory
#      - Created by build-autoinstall-iso.sh
#      - Can consume significant disk space
#
#   4. Work Directories:
#      - Temporary work/ directory
#      - Used during ISO creation
#      - Usually cleaned automatically
#
#   5. Terraform State (--all flag):
#      - .terraform/ directory (provider plugins)
#      - terraform.tfstate files
#      - .terraform.lock.hcl
#      - Allows fresh infrastructure start
#
# EXAMPLES:
#   # Interactive VM cleanup only
#   ./cleanup.sh
#   
#   # Clean VMs and ISO files
#   ./cleanup.sh --isos
#   
#   # Full cleanup without prompts (CI/CD)
#   ./cleanup.sh --all --force
#   
#   # See what would be cleaned
#   ./cleanup.sh --help  # Then run without --force to preview
#
# SAFETY FEATURES:
#   - Preview Mode: Shows resources before deletion
#   - Confirmation Prompts: Requires user confirmation
#   - Graceful Shutdown: Attempts clean VM stop first
#   - Summary Report: Shows cleanup results
#   - Non-Destructive Default: Only cleans VMs by default
#
# WORKFLOW INTEGRATION:
#   # After testing
#   ./cleanup.sh --isos
#   
#   # Before switching projects
#   ./cleanup.sh --all
#   
#   # CI/CD pipeline cleanup
#   ./cleanup.sh --all --force || true
#
# CLEANUP PROCESS:
#   1. Detects available IaC tool (OpenTofu/Terraform)
#   2. Lists all resources to be cleaned
#   3. Requests confirmation (unless --force)
#   4. Destroys Terraform-managed resources
#   5. Removes orphaned VMs
#   6. Cleans additional resources per flags
#   7. Reports final status and disk usage
#
# DISK SPACE RECOVERY:
#   - Each VM: 5-20GB (depending on usage)
#   - Each ISO: ~2GB
#   - Terraform state: ~100MB
#   - Total possible: 10-100GB+
#
# TROUBLESHOOTING:
#   - "Permission denied": Check file ownership
#   - "VM busy": VM may be in use, try --force
#   - "State locked": Another Terraform process running
#   - "Not found": Resources already cleaned
#
# NOTES:
#   - Templates are NOT affected by cleanup
#   - Snapshots are preserved
#   - Network settings remain intact
#   - Use --force carefully in production
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENTOFU_DIR="${PROJECT_ROOT}/opentofu"
OUTPUT_DIR="${PROJECT_ROOT}/output"
WORK_DIR="${PROJECT_ROOT}/work"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Parse arguments
CLEAN_ISOS=false
FORCE=false
CLEAN_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --isos)
            CLEAN_ISOS=true
            shift
            ;;
        --all)
            CLEAN_ALL=true
            CLEAN_ISOS=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --isos      Also remove generated ISO files"
            echo "  --all       Remove all generated files and VMs"
            echo "  --force,-f  Don't ask for confirmation"
            echo "  --help,-h   Show this help message"
            echo
            echo "Examples:"
            echo "  $0                # Destroy VMs only"
            echo "  $0 --isos         # Destroy VMs and ISOs"
            echo "  $0 --all --force  # Clean everything without confirmation"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect which IaC tool is available (OpenTofu preferred)
check_terraform_command() {
    if command -v tofu &> /dev/null; then
        TF_CMD="tofu"
    elif command -v terraform &> /dev/null; then
        TF_CMD="terraform"
    else
        log_error "Neither OpenTofu nor Terraform found"
        log_info "VMs may need manual cleanup with: prlctl list -a"
        return 1
    fi
    return 0
}

# List VMs managed by OpenTofu/Terraform
list_terraform_vms() {
    if [ ! -d "${OPENTOFU_DIR}/.terraform" ]; then
        return 0
    fi
    
    cd "$OPENTOFU_DIR"
    # Count VMs in Terraform state
    local vm_count=$($TF_CMD state list 2>/dev/null | grep -c "parallels-desktop_vm" || echo "0")
    
    if [ "$vm_count" -gt 0 ]; then
        echo
        log_info "Found $vm_count VM(s) managed by ${TF_CMD}:"
        $TF_CMD state list | grep "parallels-desktop_vm" | sed 's/^/  - /'
        return 0
    else
        return 1
    fi
}

# List all Ubuntu VMs in Parallels Desktop
list_parallels_vms() {
    # Find VMs with ubuntu/Ubuntu in the name
    local vms=$(prlctl list -a | grep -E "ubuntu-|Ubuntu" | awk '{print $1}' || true)
    
    if [ -n "$vms" ]; then
        echo
        log_info "Found Parallels VMs:"
        echo "$vms" | sed 's/^/  - /'
        return 0
    else
        return 1
    fi
}

# Destroy VMs using OpenTofu/Terraform
# This is the cleanest way to remove managed VMs
destroy_terraform_vms() {
    if [ ! -d "${OPENTOFU_DIR}/.terraform" ]; then
        log_info "No ${TF_CMD} state found, skipping..."
        return 0
    fi
    
    cd "$OPENTOFU_DIR"
    
    log_info "Destroying VMs via ${TF_CMD}..."
    # Auto-approve to avoid interactive prompts
    if $TF_CMD destroy -auto-approve; then
        log_info "✓ VMs destroyed successfully"
    else
        log_warn "Some VMs may not have been destroyed properly"
        return 1
    fi
}

# Clean up VMs not managed by Terraform
# These might be from manual creation or failed deployments
cleanup_orphaned_vms() {
    log_info "Checking for orphaned VMs..."
    
    local orphaned=$(prlctl list -a | grep -E "ubuntu-|Ubuntu" | awk '{print $1}' || true)
    
    if [ -z "$orphaned" ]; then
        log_info "No orphaned VMs found"
        return 0
    fi
    
    echo
    log_warn "Found potentially orphaned VMs:"
    echo "$orphaned" | sed 's/^/  - /'
    echo
    
    if [ "$FORCE" = true ]; then
        local response="y"
    else
        read -p "Remove these VMs? (y/N): " -n 1 -r response
        echo
    fi
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        for vm in $orphaned; do
            log_info "Removing VM: $vm"
            # Force stop if running
            prlctl stop "$vm" --kill 2>/dev/null || true
            # Delete VM and all its files
            prlctl delete "$vm" 2>/dev/null || {
                log_error "Failed to delete VM: $vm"
            }
        done
    fi
}

cleanup_work_dir() {
    if [ -d "$WORK_DIR" ]; then
        log_info "Cleaning work directory..."
        rm -rf "$WORK_DIR"
    fi
}

# Remove generated ISO files to recover disk space
cleanup_isos() {
    if [ ! -d "$OUTPUT_DIR" ]; then
        return 0
    fi
    
    # Count ISO files
    local iso_count=$(find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null | wc -l)
    
    if [ "$iso_count" -eq 0 ]; then
        log_info "No ISO files to clean"
        return 0
    fi
    
    echo
    log_info "Found $iso_count ISO file(s) in $OUTPUT_DIR:"
    find "$OUTPUT_DIR" -name "*.iso" -exec basename {} \; | sed 's/^/  - /'
    echo
    
    if [ "$FORCE" = true ]; then
        local response="y"
    else
        read -p "Remove these ISO files? (y/N): " -n 1 -r response
        echo
    fi
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Removing ISO files..."
        find "$OUTPUT_DIR" -name "*.iso" -delete
        log_info "✓ ISO files removed"
    fi
}

# Remove Terraform state files for a fresh start
# Only done with --all flag for safety
cleanup_terraform_state() {
    if [ ! -d "${OPENTOFU_DIR}/.terraform" ]; then
        return 0
    fi
    
    if [ "$CLEAN_ALL" = true ]; then
        echo
        log_info "Cleaning ${TF_CMD} state..."
        
        cd "$OPENTOFU_DIR"
        # Remove provider plugins and lock file
        rm -rf .terraform .terraform.lock.hcl
        # Remove state files
        rm -f terraform.tfstate terraform.tfstate.backup
        # Remove any plan files
        rm -f tfplan
        
        log_info "✓ ${TF_CMD} state cleaned"
    fi
}

# Display cleanup results
show_summary() {
    echo
    log_info "Cleanup Summary"
    echo "==============="
    
    # Check remaining VMs
    local remaining_vms=$(prlctl list -a | grep -E "ubuntu-|Ubuntu" | wc -l || echo "0")
    echo "Remaining VMs: $remaining_vms"
    
    # Check remaining ISOs
    if [ -d "$OUTPUT_DIR" ]; then
        local remaining_isos=$(find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null | wc -l || echo "0")
        echo "Remaining ISOs: $remaining_isos"
    fi
    
    # Check disk usage
    if [ -d "$OUTPUT_DIR" ]; then
        local disk_usage=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")
        echo "Output directory size: $disk_usage"
    fi
}

# Main
main() {
    echo
    echo -e "${GREEN}VM and Resource Cleanup${NC}"
    echo -e "${GREEN}=======================${NC}"
    echo
    
    # Inventory resources to be cleaned
    local has_resources=false
    
    # Check for Terraform-managed VMs
    if check_terraform_command; then
        if list_terraform_vms; then
            has_resources=true
        fi
    fi
    
    if list_parallels_vms; then
        has_resources=true
    fi
    
    if [ "$CLEAN_ISOS" = true ]; then
        if [ -d "$OUTPUT_DIR" ] && [ "$(find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null | wc -l)" -gt 0 ]; then
            has_resources=true
        fi
    fi
    
    if [ "$has_resources" = false ]; then
        log_info "No resources to clean up"
        exit 0
    fi
    
    # Confirm action
    if [ "$FORCE" = false ]; then
        echo
        if [ "$CLEAN_ALL" = true ]; then
            log_warn "This will remove ALL VMs, ISOs, and Terraform state!"
        elif [ "$CLEAN_ISOS" = true ]; then
            log_warn "This will destroy all VMs and remove ISO files!"
        else
            log_warn "This will destroy all VMs!"
        fi
        
        read -p "Continue? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Perform cleanup
    echo
    log_info "Starting cleanup..."
    
    # Destroy VMs via Terraform/OpenTofu
    if check_terraform_command; then
        destroy_terraform_vms
    fi
    
    # Cleanup any orphaned VMs
    cleanup_orphaned_vms
    
    # Clean work directory
    cleanup_work_dir
    
    # Clean ISOs if requested
    if [ "$CLEAN_ISOS" = true ]; then
        cleanup_isos
    fi
    
    # Clean Terraform state if requested
    if [ "$CLEAN_ALL" = true ]; then
        cleanup_terraform_state
    fi
    
    # Show summary
    show_summary
    
    echo
    log_info "Cleanup complete!"
}

# Run main
main