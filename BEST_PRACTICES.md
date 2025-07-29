# Ubuntu Kickstart Best Practices

This document outlines production-proven best practices for Ubuntu Kickstart automation, covering directory structure, security, testing, and maintenance strategies.

## Table of Contents

1. [Directory Structure Recommendations](#directory-structure-recommendations)
2. [Kickstart File Organization](#kickstart-file-organization)
3. [Security Considerations](#security-considerations)
4. [Testing Strategies](#testing-strategies)
5. [Version Control Practices](#version-control-practices)
6. [Maintenance and Updates](#maintenance-and-updates)

## Directory Structure Recommendations

### Recommended Repository Layout

```
kickstart/
├── configs/                      # Kickstart configurations
│   ├── base/                    # Base configurations (inherited)
│   │   ├── common.yaml          # Common settings
│   │   ├── security.yaml        # Security baseline
│   │   └── network.yaml         # Network defaults
│   ├── roles/                   # Role-specific configs
│   │   ├── webserver/
│   │   ├── database/
│   │   └── kubernetes/
│   ├── environments/            # Environment-specific
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── regions/                 # Region-specific
│       ├── us-east/
│       ├── us-west/
│       └── eu-central/
├── scripts/                     # Automation scripts
│   ├── generate/                # Config generators
│   ├── validate/                # Validation tools
│   ├── deploy/                  # Deployment scripts
│   └── test/                    # Testing utilities
├── templates/                   # Jinja2/other templates
│   ├── storage/
│   ├── network/
│   └── users/
├── inventory/                   # Asset tracking
│   ├── hardware/
│   ├── networks/
│   └── credentials/
├── docs/                        # Documentation
│   ├── runbooks/
│   ├── architecture/
│   └── decisions/
└── tests/                       # Test suites
    ├── unit/
    ├── integration/
    └── compliance/
```

### Directory Naming Conventions

- Use lowercase with hyphens for separation
- Avoid spaces and special characters
- Keep names descriptive but concise
- Use consistent naming patterns

```bash
# Good examples
ubuntu-22.04-webserver.cfg
prod-db-primary.yaml
security-baseline-v2.yaml

# Avoid
UbuntuWebServer.cfg
prod_DB_Primary.yaml
security baseline (v2).yaml
```

## Kickstart File Organization

### Modular Configuration Approach

#### Base Configuration Template

```yaml
# base/common.yaml
#cloud-config
autoinstall:
  version: 1
  
  # Refresh installer
  refresh-installer:
    update: yes
    
  # Common locale settings
  locale: en_US.UTF-8
  
  # Standard keyboard
  keyboard:
    layout: us
    
  # Time synchronization
  timezone: UTC
  
  # APT configuration
  apt:
    preserve_sources_list: false
    primary:
      - arches: [amd64]
        uri: "http://archive.ubuntu.com/ubuntu"
    security:
      - arches: [amd64]
        uri: "http://security.ubuntu.com/ubuntu"
```

#### Role-Specific Overlay

```yaml
# roles/webserver/nginx.yaml
#cloud-config
autoinstall:
  # Include base configuration
  # (merged programmatically)
  
  # Web server specific packages
  packages:
    - nginx
    - certbot
    - python3-certbot-nginx
    - ufw
    
  # Web server late commands
  late-commands:
    - curtin in-target --target=/target -- systemctl enable nginx
    - curtin in-target --target=/target -- ufw allow 'Nginx Full'
```

### Configuration Inheritance Pattern

```python
#!/usr/bin/env python3
# scripts/generate/merge-configs.py

import yaml
from pathlib import Path

def merge_configs(base_path, overlays):
    """Merge multiple YAML configurations."""
    config = {}
    
    # Load base configuration
    with open(base_path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Apply overlays in order
    for overlay_path in overlays:
        with open(overlay_path, 'r') as f:
            overlay = yaml.safe_load(f)
            deep_merge(config, overlay)
    
    return config

def deep_merge(base, overlay):
    """Recursively merge overlay into base."""
    for key, value in overlay.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
```

### Variable Management

```yaml
# Use cloud-init's Jinja2 templating
#cloud-config
## template: jinja
autoinstall:
  version: 1
  
  identity:
    hostname: {{ hostname }}
    username: {{ admin_user }}
    password: {{ admin_password_hash }}
    
  network:
    ethernets:
      {{ primary_interface }}:
        addresses:
          - {{ ip_address }}/{{ subnet_mask }}
        gateway4: {{ gateway }}
        nameservers:
          addresses: {{ dns_servers }}
```

## Security Considerations

### Credential Management

#### Never Hardcode Secrets

```yaml
# BAD - Never do this
identity:
  password: "plaintextpassword"
  
# GOOD - Use hashed passwords
identity:
  password: "$6$rounds=4096$salt$hashedpassword"
```

#### Secure Password Generation

```bash
#!/bin/bash
# scripts/generate/secure-password.sh

# Generate random password
PASSWORD=$(openssl rand -base64 32)

# Create salted hash
SALT=$(openssl rand -base64 16 | tr -d "=+/")
HASH=$(openssl passwd -6 -salt "$SALT" "$PASSWORD")

# Store securely
echo "Password: $PASSWORD" | gpg --encrypt --recipient admin@example.com
echo "Hash: $HASH"
```

### SSH Key Management

```yaml
# SSH configuration with security best practices
ssh:
  install-server: true
  allow-pw: false  # Disable password authentication
  authorized-keys:
    # Pull from secure key management system
    - "{{ lookup('vault', 'ssh-keys/admin') }}"
```

### Network Security Baseline

```yaml
# security/network-hardening.yaml
late-commands:
  # Configure UFW firewall
  - curtin in-target --target=/target -- ufw default deny incoming
  - curtin in-target --target=/target -- ufw default allow outgoing
  - curtin in-target --target=/target -- ufw limit ssh/tcp
  - curtin in-target --target=/target -- ufw --force enable
  
  # Disable unnecessary services
  - curtin in-target --target=/target -- systemctl disable cups
  - curtin in-target --target=/target -- systemctl disable avahi-daemon
  
  # Kernel hardening
  - |
    cat <<EOF >> /target/etc/sysctl.d/99-security.conf
    # IP Spoofing protection
    net.ipv4.conf.all.rp_filter = 1
    net.ipv4.conf.default.rp_filter = 1
    
    # Ignore ICMP redirects
    net.ipv4.conf.all.accept_redirects = 0
    net.ipv6.conf.all.accept_redirects = 0
    
    # Ignore send redirects
    net.ipv4.conf.all.send_redirects = 0
    
    # Disable source packet routing
    net.ipv4.conf.all.accept_source_route = 0
    net.ipv6.conf.all.accept_source_route = 0
    
    # Log Martians
    net.ipv4.conf.all.log_martians = 1
    
    # Ignore ICMP ping requests
    net.ipv4.icmp_echo_ignore_broadcasts = 1
    EOF
```

### Package Security

```yaml
# Minimal package selection
packages:
  # Only essential packages
  - ubuntu-minimal
  - openssh-server
  - python3-minimal
  
# Security updates
late-commands:
  # Enable unattended upgrades
  - curtin in-target --target=/target -- apt-get install -y unattended-upgrades
  - |
    cat <<EOF > /target/etc/apt/apt.conf.d/50unattended-upgrades
    Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}-security";
        "\${distro_id}ESMApps:\${distro_codename}-apps-security";
        "\${distro_id}ESM:\${distro_codename}-infra-security";
    };
    Unattended-Upgrade::AutoFixInterruptedDpkg "true";
    Unattended-Upgrade::MinimalSteps "true";
    Unattended-Upgrade::Remove-Unused-Dependencies "true";
    Unattended-Upgrade::Automatic-Reboot "true";
    Unattended-Upgrade::Automatic-Reboot-Time "02:00";
    EOF
```

## Testing Strategies

### Automated Testing Pipeline

```yaml
# .gitlab-ci.yml or .github/workflows/test.yml
stages:
  - validate
  - build
  - test
  - deploy

validate:kickstart:
  stage: validate
  script:
    - ./scripts/validate/syntax-check.sh
    - ./scripts/validate/security-audit.sh
    
test:vm:
  stage: test
  script:
    - ./scripts/test/spawn-test-vm.sh
    - ./scripts/test/run-integration-tests.sh
    - ./scripts/test/compliance-check.sh
```

### Validation Script

```bash
#!/bin/bash
# scripts/validate/validate-kickstart.sh

set -euo pipefail

CONFIG_FILE="$1"

echo "Validating Kickstart configuration: $CONFIG_FILE"

# Check YAML syntax
echo "Checking YAML syntax..."
python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))"

# Validate cloud-config
echo "Validating cloud-config schema..."
cloud-init devel schema --config-file "$CONFIG_FILE"

# Security checks
echo "Running security audit..."
grep -q "allow-pw: false" "$CONFIG_FILE" || echo "WARNING: Password authentication enabled"
grep -q "unattended-upgrades" "$CONFIG_FILE" || echo "WARNING: Automatic updates not configured"

# Check for hardcoded passwords
if grep -qE "(password|passwd):\s*['\"]?[^$]" "$CONFIG_FILE"; then
    echo "ERROR: Plaintext password detected!"
    exit 1
fi

echo "Validation complete!"
```

### Integration Testing

```bash
#!/bin/bash
# scripts/test/integration-test.sh

# Test VM deployment
deploy_test_vm() {
    local config="$1"
    local vm_name="test-$(date +%s)"
    
    virt-install \
        --name "$vm_name" \
        --memory 2048 \
        --vcpus 2 \
        --disk size=10 \
        --os-variant ubuntu22.04 \
        --network network=default \
        --graphics none \
        --console pty,target_type=serial \
        --location ubuntu-22.04.iso \
        --initrd-inject="$config" \
        --extra-args="autoinstall" \
        --noautoconsole
        
    # Wait for installation
    while virsh list --all | grep -q "$vm_name.*running"; do
        sleep 10
    done
    
    # Run tests
    run_vm_tests "$vm_name"
}

run_vm_tests() {
    local vm_name="$1"
    local ip=$(virsh domifaddr "$vm_name" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
    
    # Test SSH connectivity
    ssh -o StrictHostKeyChecking=no ubuntu@"$ip" "echo 'SSH test passed'"
    
    # Verify packages
    ssh ubuntu@"$ip" "dpkg -l | grep -q nginx"
    
    # Check security settings
    ssh ubuntu@"$ip" "sudo ufw status | grep -q active"
}
```

## Version Control Practices

### Git Workflow

```bash
# .gitignore
# Sensitive data
*.pem
*.key
*_rsa
*_rsa.pub
credentials/
secrets/

# Generated files
output/
*.iso
*.img

# Test artifacts
.vagrant/
*.log
test-results/

# IDE
.vscode/
.idea/
```

### Branch Strategy

```
main
├── develop
│   ├── feature/add-kubernetes-support
│   ├── feature/security-hardening-v2
│   └── bugfix/network-config-issue
├── staging
└── release/v1.2.0
```

### Commit Message Standards

```bash
# Format: <type>(<scope>): <subject>

feat(webserver): add nginx auto-tuning configuration
fix(network): correct MTU settings for 10Gb interfaces
docs(security): update CIS benchmark compliance notes
test(storage): add LVM configuration validation
refactor(scripts): modularize configuration generator
```

### Pre-commit Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Run validation on changed Kickstart files
for file in $(git diff --cached --name-only | grep -E '\.(cfg|yaml|yml)$'); do
    if [[ -f "$file" ]]; then
        ./scripts/validate/validate-kickstart.sh "$file" || exit 1
    fi
done

# Check for secrets
if git diff --cached | grep -qE "(password|secret|key).*=.*['\"]?[^$]"; then
    echo "ERROR: Possible secret detected in commit"
    exit 1
fi
```

## Maintenance and Updates

### Update Strategy

```bash
#!/bin/bash
# scripts/maintenance/update-configs.sh

# Update package lists
update_package_lists() {
    echo "Updating package lists..."
    
    # Update security packages
    curl -s https://ubuntu.com/security/notices.json | \
        jq '.notices[] | select(.release=="22.04") | .packages[]' > security-updates.txt
}

# Test updates in staging
test_updates() {
    for config in configs/staging/*.yaml; do
        ./scripts/test/deploy-test.sh "$config"
    done
}
```

### Configuration Auditing

```python
#!/usr/bin/env python3
# scripts/audit/config-audit.py

import yaml
import json
from datetime import datetime
from pathlib import Path

def audit_configs(config_dir):
    """Audit all Kickstart configurations."""
    audit_report = {
        'timestamp': datetime.now().isoformat(),
        'configs': []
    }
    
    for config_file in Path(config_dir).glob('**/*.yaml'):
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
            
        audit_entry = {
            'file': str(config_file),
            'checks': {
                'ssh_hardened': check_ssh_hardening(config),
                'firewall_enabled': check_firewall(config),
                'updates_enabled': check_updates(config),
                'minimal_packages': check_minimal_packages(config)
            }
        }
        
        audit_report['configs'].append(audit_entry)
    
    return audit_report

def check_ssh_hardening(config):
    """Verify SSH is properly hardened."""
    ssh_config = config.get('autoinstall', {}).get('ssh', {})
    return ssh_config.get('allow-pw', True) == False

def check_firewall(config):
    """Check if firewall is configured."""
    commands = config.get('autoinstall', {}).get('late-commands', [])
    return any('ufw' in cmd for cmd in commands)
```

### Monitoring and Alerting

```yaml
# monitoring/prometheus-rules.yaml
groups:
  - name: kickstart_deployment
    rules:
      - alert: DeploymentFailure
        expr: kickstart_deployment_failed > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kickstart deployment failed"
          
      - alert: ConfigurationDrift
        expr: kickstart_config_drift > 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Configuration drift detected"
```

## Performance Optimization

### Parallel Deployments

```bash
#!/bin/bash
# scripts/deploy/parallel-deploy.sh

deploy_systems() {
    local max_parallel=10
    local count=0
    
    for target in $(cat deployment-targets.txt); do
        deploy_single_system "$target" &
        
        ((count++))
        if [[ $count -ge $max_parallel ]]; then
            wait -n
            ((count--))
        fi
    done
    
    wait
}
```

### Caching Strategies

```yaml
# Use local APT mirror
apt:
  primary:
    - arches: [amd64]
      uri: "http://apt-mirror.internal/ubuntu"
  security:
    - arches: [amd64]
      uri: "http://apt-mirror.internal/ubuntu-security"
```

## Compliance and Documentation

### Compliance Tracking

```yaml
# compliance/cis-benchmark.yaml
compliance:
  framework: CIS
  version: 1.1.0
  controls:
    - id: 1.1.1
      description: "Disable unused filesystems"
      implementation: |
        late-commands:
          - echo "install cramfs /bin/true" >> /target/etc/modprobe.d/cis.conf
    - id: 2.1.1
      description: "Ensure xinetd is not installed"
      implementation: |
        packages:
          - "!xinetd"
```

### Change Management

```markdown
# docs/decisions/ADR-001-kickstart-framework.md
# Architecture Decision Record: Kickstart Framework Selection

## Status
Accepted

## Context
Need to standardize Ubuntu deployment automation across 1000+ servers.

## Decision
Use Ubuntu's native Kickstart support via Subiquity installer.

## Consequences
- Positive: Native support, cloud-init integration
- Negative: Limited to Ubuntu 20.04+
- Risk: Feature parity with Preseed

## References
- Ubuntu Autoinstall Documentation
- Internal deployment metrics
```

## Summary

Following these best practices ensures:

1. **Maintainability**: Modular, well-organized configurations
2. **Security**: Hardened by default, secrets properly managed
3. **Reliability**: Thoroughly tested before production
4. **Scalability**: Efficient deployment at scale
5. **Compliance**: Audit trails and documentation

Remember: automation is only as good as its maintenance. Regularly review, test, and update your configurations to meet evolving requirements.