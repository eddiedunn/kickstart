#!/bin/bash
#
# Deploy VMs using OpenTofu/Terraform
# Wrapper script for easy VM deployment
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

check_prerequisites() {
    local missing=()
    
    # Check for OpenTofu or Terraform
    if command -v tofu &> /dev/null; then
        TF_CMD="tofu"
    elif command -v terraform &> /dev/null; then
        TF_CMD="terraform"
    else
        missing+=("OpenTofu/Terraform")
    fi
    
    # Check for Parallels Desktop
    if ! command -v prlctl &> /dev/null; then
        missing+=("Parallels Desktop")
    fi
    
    # Check for required files
    if [ ! -f "${OPENTOFU_DIR}/terraform.tfvars" ]; then
        if [ -f "${OPENTOFU_DIR}/terraform.tfvars.example" ]; then
            log_warn "terraform.tfvars not found. Creating from example..."
            cp "${OPENTOFU_DIR}/terraform.tfvars.example" "${OPENTOFU_DIR}/terraform.tfvars"
            log_info "Please edit ${OPENTOFU_DIR}/terraform.tfvars to set your ISO path"
            exit 1
        else
            missing+=("terraform.tfvars")
        fi
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites: ${missing[*]}"
        echo
        echo "Installation instructions:"
        echo "  - OpenTofu: brew install opentofu"
        echo "  - Terraform: brew install terraform"
        echo "  - Parallels: Download from parallels.com"
        exit 1
    fi
}

validate_iso_paths() {
    log_info "Validating ISO paths in configuration..."
    
    # Extract ISO paths from tfvars
    local iso_paths=$(grep -E 'iso_path\s*=' "${OPENTOFU_DIR}/terraform.tfvars" | \
                     sed -E 's/.*iso_path\s*=\s*"([^"]+)".*/\1/' | \
                     sort -u)
    
    local missing_isos=()
    for iso in $iso_paths; do
        # Resolve relative paths from opentofu directory
        local full_path="${iso}"
        if [[ ! "$iso" = /* ]]; then
            full_path="${OPENTOFU_DIR}/${iso}"
        fi
        
        if [ ! -f "$full_path" ]; then
            missing_isos+=("$iso")
        else
            log_info "✓ Found ISO: $(basename "$iso")"
        fi
    done
    
    if [ ${#missing_isos[@]} -gt 0 ]; then
        log_error "Missing ISO files:"
        for iso in "${missing_isos[@]}"; do
            echo "  - $iso"
        done
        echo
        echo "Build an ISO first with:"
        echo "  ./scripts/build-autoinstall-iso.sh <ubuntu-iso>"
        exit 1
    fi
}

init_terraform() {
    log_info "Initializing ${TF_CMD}..."
    cd "$OPENTOFU_DIR"
    
    if [ ! -d ".terraform" ]; then
        $TF_CMD init || {
            log_error "Failed to initialize ${TF_CMD}"
            exit 1
        }
    else
        log_info "Already initialized"
    fi
}

plan_deployment() {
    log_info "Planning deployment..."
    cd "$OPENTOFU_DIR"
    
    $TF_CMD plan -out=tfplan || {
        log_error "Planning failed"
        exit 1
    }
    
    echo
    read -p "Review the plan above. Deploy? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        rm -f tfplan
        exit 0
    fi
}

deploy_vms() {
    log_info "Deploying VMs..."
    cd "$OPENTOFU_DIR"
    
    $TF_CMD apply tfplan || {
        log_error "Deployment failed"
        rm -f tfplan
        exit 1
    }
    
    rm -f tfplan
}

wait_for_vms() {
    log_info "Waiting for VMs to complete installation..."
    echo
    echo "This typically takes 5-10 minutes per VM."
    echo "VMs are installing Ubuntu in the background."
    echo
    
    # Get list of deployed VMs
    local vm_names=$($TF_CMD output -json vm_info 2>/dev/null | \
                    jq -r '.[] | .name' 2>/dev/null || echo "")
    
    if [ -z "$vm_names" ]; then
        log_warn "Could not get VM list from ${TF_CMD}"
        return
    fi
    
    echo "Deployed VMs:"
    for vm in $vm_names; do
        echo "  - $vm"
    done
    echo
    
    # Simple wait with status checks
    local max_wait=600  # 10 minutes
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        echo -ne "\rWaiting... ${waited}s / ${max_wait}s"
        sleep 10
        waited=$((waited + 10))
        
        # Check if any VM is still installing
        local installing=false
        for vm in $vm_names; do
            if prlctl exec "$vm" test -f /var/log/installer/autoinstall-user-data 2>/dev/null; then
                if ! prlctl exec "$vm" test -f /var/lib/cloud/instance/boot-finished 2>/dev/null; then
                    installing=true
                fi
            fi
        done
        
        if [ "$installing" = false ]; then
            echo -e "\n"
            log_info "All VMs appear to have completed installation!"
            break
        fi
    done
    
    if [ $waited -ge $max_wait ]; then
        echo -e "\n"
        log_warn "Maximum wait time reached. VMs may still be installing."
    fi
}

show_connection_info() {
    echo
    log_info "Deployment Complete!"
    echo "==================="
    echo
    
    # Try to get VM IPs
    cd "$OPENTOFU_DIR"
    local vm_names=$($TF_CMD output -json vm_info 2>/dev/null | \
                    jq -r '.[] | .name' 2>/dev/null || echo "")
    
    if [ -n "$vm_names" ]; then
        echo "VM Status:"
        for vm in $vm_names; do
            echo -n "  $vm: "
            
            # Try to get IP
            local ip=$(prlctl exec "$vm" ip addr show 2>/dev/null | \
                      grep -E 'inet .* scope global' | \
                      head -1 | awk '{print $2}' | cut -d/ -f1 || echo "")
            
            if [ -n "$ip" ]; then
                echo -e "${GREEN}Running${NC} - IP: $ip"
                echo "    SSH: ssh ubuntu@$ip"
            else
                echo -e "${YELLOW}Starting${NC} - Waiting for network..."
            fi
        done
        echo
    fi
    
    echo "Useful commands:"
    echo "  List VMs:        prlctl list -a"
    echo "  VM Status:       ./scripts/status.sh"
    echo "  Destroy VMs:     ./scripts/cleanup.sh"
    echo "  Connect to VM:   ssh ubuntu@<ip-address>"
    echo
    echo "Note: If VMs don't have IPs yet, wait a moment and run:"
    echo "  ./scripts/status.sh"
}

# Main
main() {
    echo
    echo -e "${GREEN}OpenTofu/Terraform VM Deployment${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Validate configuration
    validate_iso_paths
    
    # Initialize if needed
    init_terraform
    
    # Plan deployment
    plan_deployment
    
    # Deploy
    deploy_vms
    
    # Wait for VMs
    wait_for_vms
    
    # Show connection info
    show_connection_info
}

# Run main
main "$@"