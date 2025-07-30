#!/bin/bash
#
# Simple deployment script for testing Parallels VM creation
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENTOFU_DIR="${PROJECT_ROOT}/opentofu"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for OpenTofu or Terraform
    if command -v tofu &> /dev/null; then
        TF_CMD="tofu"
    elif command -v terraform &> /dev/null; then
        TF_CMD="terraform"
    else
        log_error "OpenTofu or Terraform not found"
        echo "Install with: brew install opentofu"
        exit 1
    fi
    
    # Check for Parallels Desktop
    if ! command -v prlctl &> /dev/null; then
        log_error "Parallels Desktop not found"
        exit 1
    fi
    
    # Check Parallels is running
    if ! prlctl list &> /dev/null; then
        log_error "Parallels Desktop is not running"
        echo "Please start Parallels Desktop and try again"
        exit 1
    fi
}

# Deploy VM
deploy_vm() {
    cd "$OPENTOFU_DIR"
    
    # Use the simple configuration
    log_info "Using simplified configuration..."
    
    # Initialize
    log_info "Initializing ${TF_CMD}..."
    $TF_CMD init || {
        log_error "Failed to initialize"
        exit 1
    }
    
    # Plan
    log_info "Planning deployment..."
    $TF_CMD plan -var-file=terraform.tfvars -state=terraform-simple.tfstate || {
        log_error "Planning failed"
        exit 1
    }
    
    # Apply
    read -p "Deploy VM? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deploying VM..."
        $TF_CMD apply -var-file=terraform.tfvars -state=terraform-simple.tfstate -auto-approve || {
            log_error "Deployment failed"
            exit 1
        }
    else
        log_info "Deployment cancelled"
        exit 0
    fi
}

# Show VM info
show_vm_info() {
    echo
    log_info "VM deployed successfully!"
    echo
    
    # Get VM name
    local vm_name=$($TF_CMD output -state=terraform-simple.tfstate -raw vm_name 2>/dev/null || echo "ubuntu-server")
    
    echo "VM Status:"
    prlctl list -i "$vm_name" 2>/dev/null || echo "VM is starting..."
    
    echo
    echo "To connect to the VM:"
    echo "  1. Wait for installation to complete (5-10 minutes)"
    echo "  2. Get VM IP: prlctl exec \"$vm_name\" ip addr show"
    echo "  3. SSH: ssh ubuntu@<vm-ip>"
    echo
    echo "To destroy the VM:"
    echo "  cd $OPENTOFU_DIR"
    echo "  $TF_CMD destroy -var-file=terraform.tfvars -state=terraform-simple.tfstate"
}

# Main
main() {
    echo
    echo -e "${GREEN}Parallels VM Simple Deployment${NC}"
    echo -e "${GREEN}==============================${NC}"
    echo
    
    check_prerequisites
    
    # Check ISO exists
    ISO_PATH="${PROJECT_ROOT}/output/ubuntu-22.04.5-autoinstall-arm64.iso"
    if [ ! -f "$ISO_PATH" ]; then
        log_error "ISO not found: $ISO_PATH"
        exit 1
    fi
    log_info "Found ISO: $(basename "$ISO_PATH") ($(du -h "$ISO_PATH" | cut -f1))"
    
    # Deploy
    deploy_vm
    
    # Show info
    show_vm_info
}

# Run
main "$@"