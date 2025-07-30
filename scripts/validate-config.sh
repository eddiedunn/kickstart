#!/bin/bash
#
# Validate autoinstall configurations
# Checks cloud-init syntax and security best practices
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/configs"
AUTOINSTALL_DIR="${PROJECT_ROOT}/autoinstall"

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
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

check_prerequisites() {
    local missing=()
    
    if ! command -v cloud-init &> /dev/null; then
        missing+=("cloud-init")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites: ${missing[*]}"
        echo
        echo "Installation instructions:"
        echo "  - cloud-init: sudo apt-get install cloud-init"
        echo "  - yq: brew install yq (macOS) or snap install yq (Linux)"
        exit 1
    fi
}

validate_yaml_syntax() {
    local file="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if yq eval '.' "$file" > /dev/null 2>&1; then
        log_pass "YAML syntax valid: $(basename "$file")"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_fail "YAML syntax invalid: $(basename "$file")"
        yq eval '.' "$file" 2>&1 | sed 's/^/    /'
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

validate_cloud_init_schema() {
    local file="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # Skip if cloud-init not available
    if ! command -v cloud-init &> /dev/null; then
        log_warn "Skipping cloud-init schema validation (cloud-init not installed)"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi
    
    if cloud-init devel schema --config-file "$file" &> /dev/null; then
        log_pass "Cloud-init schema valid: $(basename "$file")"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_fail "Cloud-init schema invalid: $(basename "$file")"
        cloud-init devel schema --config-file "$file" 2>&1 | grep -E "(Error|Warning)" | sed 's/^/    /'
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_security() {
    local file="$1"
    local issues=0
    
    echo "  Security checks for $(basename "$file"):"
    
    # Check for plaintext passwords
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -E 'password:\s*[^$]' "$file" | grep -v '#' | grep -q .; then
        log_fail "    Plaintext password detected!"
        issues=$((issues + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    else
        log_pass "    No plaintext passwords"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check for weak password hashes
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -E 'password:\s*\$[16]\$' "$file" | grep -v '#' | grep -q .; then
        log_warn "    Weak password hash detected (MD5/SHA1)"
        WARNINGS=$((WARNINGS + 1))
        issues=$((issues + 1))
    else
        log_pass "    Strong password hashes only"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check SSH configuration
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if yq eval '.autoinstall.ssh.allow-pw' "$file" 2>/dev/null | grep -q "true"; then
        log_warn "    SSH password authentication enabled"
        WARNINGS=$((WARNINGS + 1))
    else
        log_pass "    SSH password authentication disabled"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check for SSH keys
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local ssh_keys=$(yq eval '.autoinstall.ssh.authorized-keys[]' "$file" 2>/dev/null | wc -l)
    if [ "$ssh_keys" -eq 0 ]; then
        ssh_keys=$(yq eval '.autoinstall.user-data.users[].ssh_authorized_keys[]' "$file" 2>/dev/null | wc -l)
    fi
    
    if [ "$ssh_keys" -gt 0 ]; then
        log_pass "    SSH keys configured: $ssh_keys key(s)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "    No SSH keys configured"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    return $issues
}

check_required_fields() {
    local file="$1"
    local missing=0
    
    echo "  Required fields for $(basename "$file"):"
    
    # Check autoinstall version
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if yq eval '.autoinstall.version' "$file" 2>/dev/null | grep -q "1"; then
        log_pass "    Autoinstall version: 1"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_fail "    Missing autoinstall version"
        missing=$((missing + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check identity section
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if yq eval '.autoinstall.identity' "$file" 2>/dev/null | grep -q "username"; then
        log_pass "    Identity section present"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_fail "    Missing identity section"
        missing=$((missing + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    # Check storage configuration
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if yq eval '.autoinstall.storage' "$file" 2>/dev/null | grep -q "layout"; then
        log_pass "    Storage configuration present"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_fail "    Missing storage configuration"
        missing=$((missing + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    return $missing
}

validate_file() {
    local file="$1"
    
    echo
    log_info "Validating: $file"
    echo "----------------------------------------"
    
    # YAML syntax check
    if ! validate_yaml_syntax "$file"; then
        return 1
    fi
    
    # Cloud-init schema validation
    validate_cloud_init_schema "$file"
    
    # Security checks
    check_security "$file"
    
    # Required fields
    check_required_fields "$file"
}

# Main
main() {
    echo
    echo -e "${GREEN}Autoinstall Configuration Validator${NC}"
    echo -e "${GREEN}===================================${NC}"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Find all user-data files
    local files=()
    
    # Check autoinstall directory
    if [ -d "$AUTOINSTALL_DIR" ]; then
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$AUTOINSTALL_DIR" -name "user-data" -type f -print0)
    fi
    
    # Check configs directory
    if [ -d "$CONFIG_DIR" ]; then
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$CONFIG_DIR" -name "*.yaml" -o -name "*.yml" -type f -print0)
    fi
    
    # Check specific file if provided
    if [ $# -gt 0 ]; then
        files=("$@")
    fi
    
    if [ ${#files[@]} -eq 0 ]; then
        log_warn "No configuration files found"
        echo
        echo "Usage: $0 [config-file]"
        echo
        echo "Or place files in:"
        echo "  - ${AUTOINSTALL_DIR}/user-data"
        echo "  - ${CONFIG_DIR}/*.yaml"
        exit 1
    fi
    
    # Validate each file
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            validate_file "$file"
        else
            log_error "File not found: $file"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
    done
    
    # Summary
    echo
    echo "========================================="
    echo -e "${GREEN}Validation Summary${NC}"
    echo "========================================="
    echo "Total checks:  $TOTAL_CHECKS"
    echo -e "Passed:        ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed:        ${RED}$FAILED_CHECKS${NC}"
    echo -e "Warnings:      ${YELLOW}$WARNINGS${NC}"
    echo
    
    if [ $FAILED_CHECKS -gt 0 ]; then
        log_error "Validation failed!"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        log_warn "Validation passed with warnings"
        exit 0
    else
        log_info "All validations passed!"
        exit 0
    fi
}

# Run main
main "$@"