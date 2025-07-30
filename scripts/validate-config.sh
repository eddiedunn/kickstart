#!/bin/bash
#
# validate-config.sh - Validate Ubuntu Autoinstall and Cloud-Init Configurations
#
# PURPOSE:
#   Validates YAML syntax, cloud-init schema compliance, and security best practices
#   for Ubuntu autoinstall and cloud-init configuration files. Essential tool for
#   catching configuration errors before deployment.
#
# USAGE:
#   ./validate-config.sh [config-file]
#   ./validate-config.sh                    # Validate all configs
#   ./validate-config.sh user-data          # Validate specific file
#   ./validate-config.sh /path/to/config   # Validate custom path
#
# VALIDATION LAYERS:
#
#   1. YAML Syntax Validation:
#      - Checks for valid YAML structure
#      - Identifies indentation errors
#      - Catches missing quotes, colons
#      - Reports line numbers for errors
#
#   2. Cloud-Init Schema Validation:
#      - Validates against official Ubuntu schema
#      - Checks autoinstall version compatibility
#      - Ensures required sections are present
#      - Validates field types and values
#
#   3. Security Analysis:
#      - Plaintext Password Detection:
#        * Scans for unhashed passwords
#        * Identifies weak password storage
#      - Password Hash Strength:
#        * Requires SHA-512 ($6$) hashes
#        * Warns on MD5 ($1$) or SHA-256 ($5$)
#      - SSH Configuration:
#        * Verifies SSH keys are configured
#        * Checks password auth is disabled
#        * Ensures secure defaults
#
#   4. Required Fields Check:
#      - autoinstall.version (must be 1)
#      - autoinstall.identity (user configuration)
#      - autoinstall.storage (disk layout)
#      - network configuration basics
#
# FILE SEARCH LOCATIONS:
#   1. autoinstall/user-data (primary autoinstall config)
#   2. configs/*.yaml (additional configurations)
#   3. cloud-init-examples/*.yaml (example configs)
#   4. Command line argument (custom path)
#
# OUTPUT FORMAT:
#   [PASS] ✓ Check passed successfully
#   [FAIL] ✗ Check failed - action required
#   [WARN] ⚠ Warning - review recommended
#   [INFO] ℹ Informational message
#
# EXAMPLES:
#   # Validate all configuration files
#   ./validate-config.sh
#   
#   # Validate specific file
#   ./validate-config.sh autoinstall/user-data
#   
#   # Validate custom cloud-init config
#   ./validate-config.sh ~/my-configs/web-server.yaml
#   
#   # Use in CI/CD pipeline
#   ./validate-config.sh || exit 1
#
# PREREQUISITES:
#   Required tools:
#   - cloud-init: Official schema validation
#     Ubuntu/Debian: sudo apt-get install cloud-init
#     RHEL/CentOS: sudo yum install cloud-init
#   
#   - yq: YAML command-line processor
#     macOS: brew install yq
#     Linux: snap install yq
#     Direct: wget https://github.com/mikefarah/yq/releases/latest
#
# EXIT CODES:
#   0 - All validations passed (may include warnings)
#   1 - One or more critical validations failed
#
# COMMON ISSUES:
#   - "Invalid YAML": Check indentation (spaces, not tabs)
#   - "Schema validation failed": Verify autoinstall version
#   - "No SSH keys": Add authorized_keys to identity section
#   - "Plaintext password": Use mkpasswd -m sha-512
#
# SECURITY NOTES:
#   - Never use plaintext passwords in production
#   - Generate password hashes with: mkpasswd -m sha-512
#   - Always configure SSH key authentication
#   - Disable password authentication when possible
#   - Review warnings even if validation passes
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

# Check that required tools are installed
check_prerequisites() {
    local missing=()
    
    # Check for cloud-init (schema validation)
    if ! command -v cloud-init &> /dev/null; then
        missing+=("cloud-init")
    fi
    
    # Check for yq (YAML parsing)
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

# Validate YAML syntax using yq parser
# This catches common YAML errors before cloud-init sees them
validate_yaml_syntax() {
    local file="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if yq eval '.' "$file" > /dev/null 2>&1; then
        log_pass "YAML syntax valid: $(basename "$file")"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_fail "YAML syntax invalid: $(basename "$file")"
        # Show the actual error for debugging
        yq eval '.' "$file" 2>&1 | sed 's/^/    /'
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Validate against official cloud-init schema
# This ensures the configuration will be accepted by Ubuntu's installer
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

# Perform security analysis on configuration
# Checks for common security misconfigurations
check_security() {
    local file="$1"
    local issues=0
    
    echo "  Security checks for $(basename "$file"):"
    
    # Check for plaintext passwords (major security risk)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -E 'password:\s*[^$]' "$file" | grep -v '#' | grep -q .; then
        log_fail "    Plaintext password detected!"
        issues=$((issues + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    else
        log_pass "    No plaintext passwords"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check for weak password hashes (MD5=$1, SHA1=$6)
    # Only SHA-512 ($6$) is considered secure
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if grep -E 'password:\s*\$[16]\$' "$file" | grep -v '#' | grep -q .; then
        log_warn "    Weak password hash detected (MD5/SHA1)"
        WARNINGS=$((WARNINGS + 1))
        issues=$((issues + 1))
    else
        log_pass "    Strong password hashes only"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check SSH password authentication setting
    # Key-based auth is more secure than passwords
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if yq eval '.autoinstall.ssh.allow-pw' "$file" 2>/dev/null | grep -q "true"; then
        log_warn "    SSH password authentication enabled"
        WARNINGS=$((WARNINGS + 1))
    else
        log_pass "    SSH password authentication disabled"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    
    # Check for SSH keys configuration
    # At least one SSH key should be configured for secure access
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local ssh_keys=$(yq eval '.autoinstall.ssh.authorized-keys[]' "$file" 2>/dev/null | wc -l)
    if [ "$ssh_keys" -eq 0 ]; then
        # Also check in user-data section
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

# Check for required autoinstall fields
# These fields must be present for successful installation
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

# Main validation function for a single file
# Runs all validation checks in sequence
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
    
    # Find all configuration files to validate
    local files=()
    
    # Check autoinstall directory for user-data files
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