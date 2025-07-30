#!/bin/bash
#
# Show status of deployed VMs
# Displays IP addresses and SSH connection commands
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
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Parse arguments
VERBOSE=false
WATCH=false
INTERVAL=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --watch|-w)
            WATCH=true
            shift
            ;;
        --interval|-i)
            INTERVAL="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --verbose,-v     Show detailed VM information"
            echo "  --watch,-w       Continuously watch VM status"
            echo "  --interval,-i N  Watch interval in seconds (default: 5)"
            echo "  --help,-h        Show this help message"
            echo
            echo "Examples:"
            echo "  $0                      # Show VM status once"
            echo "  $0 --watch              # Watch VM status continuously"
            echo "  $0 --verbose --watch    # Watch with detailed info"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

get_vm_ip() {
    local vm_name="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Try to get IP from VM
        local ip=$(prlctl exec "$vm_name" ip addr show 2>/dev/null | \
                  grep -E 'inet .* scope global' | \
                  grep -v '169.254' | \
                  head -1 | \
                  awk '{print $2}' | \
                  cut -d/ -f1 || echo "")
        
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
        
        # Try alternative method
        ip=$(prlctl list -i "$vm_name" 2>/dev/null | \
             grep "IP address:" | \
             grep -v "169.254" | \
             head -1 | \
             awk '{print $3}' || echo "")
        
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 1
    done
    
    return 1
}

get_vm_status() {
    local vm_name="$1"
    local status=$(prlctl list -i "$vm_name" 2>/dev/null | grep "State:" | awk '{print $2}' || echo "unknown")
    
    case "$status" in
        running)
            echo -e "${GREEN}Running${NC}"
            ;;
        stopped)
            echo -e "${RED}Stopped${NC}"
            ;;
        suspended)
            echo -e "${YELLOW}Suspended${NC}"
            ;;
        *)
            echo -e "${YELLOW}Unknown${NC}"
            ;;
    esac
}

check_ssh_connectivity() {
    local ip="$1"
    
    if timeout 2 nc -z "$ip" 22 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
}

show_vm_details() {
    local vm_name="$1"
    
    echo
    echo "  VM Details for $vm_name:"
    
    # Get VM info
    local vm_info=$(prlctl list -i "$vm_name" 2>/dev/null)
    
    # CPU and Memory
    local cpus=$(echo "$vm_info" | grep "CPUs:" | awk '{print $2}')
    local memory=$(echo "$vm_info" | grep "Memory size:" | awk '{print $3, $4}')
    echo "    Resources: ${cpus} CPUs, ${memory}"
    
    # Disk usage
    local disk_size=$(echo "$vm_info" | grep "Size:" | head -1 | awk '{print $2, $3}')
    echo "    Disk: ${disk_size}"
    
    # Uptime
    local uptime=$(echo "$vm_info" | grep "Uptime:" | cut -d: -f2- | xargs)
    if [ -n "$uptime" ]; then
        echo "    Uptime: ${uptime}"
    fi
    
    # Network interfaces
    echo "    Network interfaces:"
    prlctl exec "$vm_name" ip -br addr show 2>/dev/null | grep -E "UP|UNKNOWN" | sed 's/^/      /'
}

display_status() {
    # Clear screen if watching
    if [ "$WATCH" = true ]; then
        clear
    fi
    
    echo
    echo -e "${GREEN}VM Status Report${NC}"
    echo -e "${GREEN}================${NC}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    # Get list of VMs
    local vms=$(prlctl list -a | grep -E "{.*}" | grep -i ubuntu | awk '{print $1, $2}' || true)
    
    if [ -z "$vms" ]; then
        log_warn "No Ubuntu VMs found"
        
        # Check if Terraform/OpenTofu state exists
        if [ -d "${OPENTOFU_DIR}/.terraform" ]; then
            echo
            echo "Hint: Deploy VMs with: ./scripts/deploy-vm.sh"
        fi
        return
    fi
    
    # Display VM status table
    printf "%-30s %-10s %-15s %-5s %s\n" "VM Name" "Status" "IP Address" "SSH" "SSH Command"
    printf "%-30s %-10s %-15s %-5s %s\n" "-------" "------" "----------" "---" "-----------"
    
    echo "$vms" | while read -r vm_id vm_name; do
        # Skip header lines
        [[ "$vm_id" =~ ^NAME ]] && continue
        
        # Get VM status
        local status=$(get_vm_status "$vm_name")
        
        # Get IP if running
        local ip="-"
        local ssh_status="-"
        local ssh_cmd="-"
        
        if [[ "$status" =~ Running ]]; then
            if ip=$(get_vm_ip "$vm_name"); then
                ssh_status=$(check_ssh_connectivity "$ip")
                ssh_cmd="ssh ubuntu@$ip"
            else
                ip="Waiting..."
            fi
        fi
        
        # Print row
        printf "%-30s %-20s %-15s %-5s %s\n" \
            "$vm_name" "$status" "$ip" "$ssh_status" "$ssh_cmd"
        
        # Show details if verbose
        if [ "$VERBOSE" = true ] && [[ "$status" =~ Running ]]; then
            show_vm_details "$vm_name"
        fi
    done
    
    # Show summary
    echo
    local total_vms=$(echo "$vms" | wc -l)
    local running_vms=$(prlctl list -a | grep -i ubuntu | grep -c "running" || echo "0")
    echo "Total VMs: $total_vms (Running: $running_vms)"
    
    # Show helpful commands
    if [ "$WATCH" = false ]; then
        echo
        echo "Useful commands:"
        echo "  Start VM:    prlctl start <vm-name>"
        echo "  Stop VM:     prlctl stop <vm-name>"
        echo "  Restart VM:  prlctl restart <vm-name>"
        echo "  Watch mode:  $0 --watch"
    else
        echo
        echo "Press Ctrl+C to exit watch mode"
    fi
}

# Main
main() {
    if [ "$WATCH" = true ]; then
        log_info "Watching VM status (refresh every ${INTERVAL}s)..."
        
        # Trap to restore cursor on exit
        trap 'echo -e "\n"; exit' INT TERM
        
        while true; do
            display_status
            sleep "$INTERVAL"
        done
    else
        display_status
    fi
}

# Run main
main