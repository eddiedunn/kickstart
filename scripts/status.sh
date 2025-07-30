#!/bin/bash
#
# status.sh - Display Status of Deployed VMs
#
# PURPOSE:
#   Shows real-time status of all Ubuntu VMs including IP addresses,
#   SSH connectivity, and connection commands. Supports watch mode
#   for continuous monitoring. Essential tool for VM management.
#
# USAGE:
#   ./status.sh [OPTIONS]
#
# OPTIONS:
#   --verbose,-v     Show detailed VM information
#                    Includes: CPU, memory, disk, uptime, network interfaces
#   --watch,-w       Continuously monitor VM status
#                    Updates display in real-time
#   --interval,-i N  Refresh interval in seconds (default: 5)
#                    Minimum: 1, Maximum: 300
#   --help,-h        Show this help message
#
# OUTPUT COLUMNS:
#   VM Name     - Parallels VM identifier
#   Status      - Running (green), Stopped (red), Suspended (yellow)
#   IP Address  - Primary IPv4 address (DHCP assigned)
#   SSH         - Connectivity check: ✓ (connected) or ✗ (unreachable)
#   SSH Command - Ready-to-use SSH connection command
#
# STATUS INDICATORS:
#   - ${GREEN}Running${NC}   - VM is operational
#   - ${RED}Stopped${NC}   - VM is shut down
#   - ${YELLOW}Suspended${NC} - VM is paused (RAM saved)
#   - Waiting...     - VM booting, IP pending
#
# DISPLAYS:
#   Standard Mode:
#   - VM name and color-coded status
#   - IP address (when available)
#   - SSH connectivity test result
#   - Copy-paste SSH commands
#   - Summary statistics
#
#   Verbose Mode (-v):
#   - Hardware allocation (CPUs, RAM)
#   - Disk usage and size
#   - VM uptime information
#   - Network interface details
#   - IP addresses for all interfaces
#
# EXAMPLES:
#   # Quick status check
#   ./status.sh
#   
#   # Monitor deployment progress
#   ./status.sh --watch
#   
#   # Detailed monitoring with slow refresh
#   ./status.sh --verbose --watch --interval 10
#   
#   # Check specific aspects
#   ./status.sh | grep Running    # List running VMs
#   ./status.sh | grep 192.168    # Find VMs on specific subnet
#
# SSH CONNECTIVITY:
#   The script tests SSH connectivity by:
#   1. Attempting TCP connection to port 22
#   2. Using 2-second timeout to avoid hanging
#   3. Indicating success (✓) or failure (✗)
#   
#   Note: SSH check only verifies port accessibility,
#   not authentication. You still need valid credentials.
#
# WATCH MODE:
#   - Updates display in-place
#   - Press Ctrl+C to exit
#   - Useful for monitoring:
#     * VM deployment progress
#     * Reboot cycles
#     * Network changes
#     * Resource usage
#
# NETWORK DETECTION:
#   IP detection methods (in order):
#   1. Execute 'ip addr' inside VM
#   2. Parse Parallels VM information
#   3. Exclude link-local addresses (169.254.x.x)
#   4. Retry up to 5 times for booting VMs
#
# INTEGRATION:
#   Works with VMs created by:
#   - deploy-vm.sh (ISO-based)
#   - OpenTofu/Terraform (IaC)
#   - manage-templates.sh (clones)
#   - Manual Parallels creation
#
# TROUBLESHOOTING:
#   - "No VMs found": Check VM names contain 'ubuntu'
#   - "Waiting...": VM still booting, check console
#   - SSH ✗: Firewall, wrong IP, or SSH not ready
#   - No IP: Network configuration issues
#
# NOTES:
#   - Automatically detects all Ubuntu VMs
#   - Filters by name pattern (case-insensitive)
#   - Default username assumed: 'ubuntu'
#   - Requires 'nc' (netcat) for SSH checks
#   - Performance impact minimal (<1% CPU)
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

# Get VM's IP address using multiple methods
# Retries to handle VMs that are still booting
get_vm_ip() {
    local vm_name="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Method 1: Execute ip command inside VM
        local ip=$(prlctl exec "$vm_name" ip addr show 2>/dev/null | \
                  grep -E 'inet .* scope global' | \
                  grep -v '169.254' | \              # Exclude link-local
                  head -1 | \
                  awk '{print $2}' | \
                  cut -d/ -f1 || echo "")
        
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
        
        # Method 2: Get IP from Parallels VM info
        ip=$(prlctl list -i "$vm_name" 2>/dev/null | \
             grep "IP address:" | \
             grep -v "169.254" | \             # Exclude link-local
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

# Get VM status with color coding
get_vm_status() {
    local vm_name="$1"
    local status=$(prlctl list -i "$vm_name" 2>/dev/null | grep "State:" | awk '{print $2}' || echo "unknown")
    
    # Color-code status for quick visual identification
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

# Test if SSH port is accessible
# Uses netcat with timeout to avoid hanging
check_ssh_connectivity() {
    local ip="$1"
    
    # Try to connect to SSH port (22) with 2 second timeout
    if timeout 2 nc -z "$ip" 22 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"  # Checkmark
    else
        echo -e "${RED}✗${NC}"    # X mark
    fi
}

# Display detailed VM information (verbose mode)
show_vm_details() {
    local vm_name="$1"
    
    echo
    echo "  VM Details for $vm_name:"
    
    # Get comprehensive VM information
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
    
    # Network interfaces with their status
    echo "    Network interfaces:"
    # Show brief interface list with status and IPs
    prlctl exec "$vm_name" ip -br addr show 2>/dev/null | grep -E "UP|UNKNOWN" | sed 's/^/      /'
}

# Main status display function
display_status() {
    # Clear screen for watch mode to update in place
    if [ "$WATCH" = true ]; then
        clear
    fi
    
    echo
    echo -e "${GREEN}VM Status Report${NC}"
    echo -e "${GREEN}================${NC}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    # Get list of VMs (filter for Ubuntu VMs)
    # Format: {UUID} vm-name status ...
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
    
    # Display VM status table header
    # Formatted for easy reading with proper column alignment
    printf "%-30s %-10s %-15s %-5s %s\n" "VM Name" "Status" "IP Address" "SSH" "SSH Command"
    printf "%-30s %-10s %-15s %-5s %s\n" "-------" "------" "----------" "---" "-----------"
    
    echo "$vms" | while read -r vm_id vm_name; do
        # Skip header lines
        [[ "$vm_id" =~ ^NAME ]] && continue
        
        # Get VM status
        local status=$(get_vm_status "$vm_name")
        
        # Get network info only for running VMs
        local ip="-"
        local ssh_status="-"
        local ssh_cmd="-"
        
        if [[ "$status" =~ Running ]]; then
            # Try to get IP address
            if ip=$(get_vm_ip "$vm_name"); then
                ssh_status=$(check_ssh_connectivity "$ip")
                ssh_cmd="ssh ubuntu@$ip"  # Default Ubuntu username
            else
                ip="Waiting..."  # VM still booting
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
    
    # Show context-appropriate commands
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