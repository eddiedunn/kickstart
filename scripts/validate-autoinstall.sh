#!/bin/bash
#
# Validate autoinstall configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AUTOINSTALL_DIR="${PROJECT_ROOT}/autoinstall"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Validating autoinstall configuration..."
echo

# Check if files exist
if [ ! -f "${AUTOINSTALL_DIR}/user-data" ]; then
    echo -e "${RED}[ERROR]${NC} user-data file not found"
    exit 1
fi

if [ ! -f "${AUTOINSTALL_DIR}/meta-data" ]; then
    echo -e "${RED}[ERROR]${NC} meta-data file not found"
    exit 1
fi

# Validate YAML syntax
echo -n "Checking YAML syntax... "
if python3 -c "import yaml; yaml.safe_load(open('${AUTOINSTALL_DIR}/user-data'))" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "YAML syntax error in user-data"
    exit 1
fi

# Validate cloud-init schema (if available)
if command -v cloud-init &> /dev/null; then
    echo -n "Checking cloud-init schema... "
    if cloud-init devel schema --config-file "${AUTOINSTALL_DIR}/user-data" 2>&1 | grep -q "Valid cloud-config"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}WARNING${NC}"
        echo "Note: Autoinstall configs often show warnings in cloud-init schema validation"
    fi
else
    echo -e "${YELLOW}[WARN]${NC} cloud-init not installed, skipping schema validation"
fi

# Check for required autoinstall sections
echo -n "Checking required sections... "
required_sections=("version" "identity" "storage" "network")
missing_sections=()

for section in "${required_sections[@]}"; do
    if ! grep -q "^  $section:" "${AUTOINSTALL_DIR}/user-data" 2>/dev/null; then
        missing_sections+=("$section")
    fi
done

if [ ${#missing_sections[@]} -eq 0 ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Missing required sections: ${missing_sections[*]}"
    exit 1
fi

# Security checks
echo -n "Checking security settings... "
security_issues=()

# Check for plaintext passwords
if grep -q "password:.*[^$]" "${AUTOINSTALL_DIR}/user-data" 2>/dev/null; then
    security_issues+=("Possible plaintext password detected")
fi

# Check SSH settings
if grep -q "ssh_pwauth: true" "${AUTOINSTALL_DIR}/user-data" 2>/dev/null; then
    security_issues+=("SSH password authentication enabled")
fi

if [ ${#security_issues[@]} -eq 0 ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARNING${NC}"
    for issue in "${security_issues[@]}"; do
        echo "  - $issue"
    done
fi

echo
echo -e "${GREEN}Validation complete!${NC}"
echo
echo "Autoinstall configuration appears valid for Ubuntu 22.04 ARM64"