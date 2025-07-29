# Ubuntu Kickstart Automation Tools

This document provides an overview of tools and scripts for automating Ubuntu Kickstart deployments, including generators, validators, testing frameworks, and CI/CD integration.

## Table of Contents

1. [Kickstart File Generators](#kickstart-file-generators)
2. [Validation Tools](#validation-tools)
3. [Testing Frameworks](#testing-frameworks)
4. [CI/CD Integration](#cicd-integration)
5. [Deployment Tools](#deployment-tools)
6. [Monitoring and Reporting](#monitoring-and-reporting)

## Kickstart File Generators

### Interactive Configuration Generator

```python
#!/usr/bin/env python3
# scripts/generate/kickstart-generator.py

import yaml
import click
import ipaddress
from pathlib import Path
from jinja2 import Environment, FileSystemLoader
from cryptography.fernet import Fernet
import secrets
import string

class KickstartGenerator:
    """Generate Ubuntu Kickstart configurations interactively."""
    
    def __init__(self, template_dir="templates"):
        self.env = Environment(loader=FileSystemLoader(template_dir))
        self.config = {"autoinstall": {"version": 1}}
    
    def generate_password_hash(self, password):
        """Generate SHA-512 password hash."""
        import crypt
        salt = crypt.mksalt(crypt.METHOD_SHA512)
        return crypt.crypt(password, salt)
    
    def generate_config(self):
        """Interactive configuration generation."""
        click.echo("Ubuntu Kickstart Configuration Generator")
        click.echo("=" * 40)
        
        # System configuration
        self.config["autoinstall"]["identity"] = {
            "hostname": click.prompt("Hostname", default="ubuntu-server"),
            "username": click.prompt("Admin username", default="ubuntu"),
            "password": self.generate_password_hash(
                click.prompt("Admin password", hide_input=True)
            )
        }
        
        # Network configuration
        if click.confirm("Configure static IP?"):
            self.configure_static_network()
        else:
            self.configure_dhcp_network()
        
        # Storage configuration
        storage_type = click.prompt(
            "Storage layout",
            type=click.Choice(['lvm', 'direct', 'zfs', 'custom']),
            default='lvm'
        )
        self.configure_storage(storage_type)
        
        # Package selection
        self.configure_packages()
        
        # SSH configuration
        self.configure_ssh()
        
        return self.config
    
    def configure_static_network(self):
        """Configure static network settings."""
        interface = click.prompt("Network interface", default="enp0s3")
        ip = click.prompt("IP address (CIDR)", default="192.168.1.100/24")
        gateway = click.prompt("Gateway", default="192.168.1.1")
        dns = click.prompt("DNS servers (comma-separated)", 
                          default="8.8.8.8,8.8.4.4")
        
        self.config["autoinstall"]["network"] = {
            "version": 2,
            "ethernets": {
                interface: {
                    "addresses": [ip],
                    "routes": [{"to": "default", "via": gateway}],
                    "nameservers": {
                        "addresses": dns.split(",")
                    }
                }
            }
        }
    
    def save_config(self, filename):
        """Save configuration to file."""
        with open(filename, 'w') as f:
            f.write("#cloud-config\n")
            yaml.dump(self.config, f, default_flow_style=False)
        click.echo(f"Configuration saved to {filename}")

@click.command()
@click.option('--output', '-o', default='kickstart.yaml', 
              help='Output filename')
@click.option('--template', '-t', help='Use template file')
def main(output, template):
    """Generate Ubuntu Kickstart configuration."""
    generator = KickstartGenerator()
    
    if template:
        generator.load_template(template)
    
    config = generator.generate_config()
    generator.save_config(output)

if __name__ == "__main__":
    main()
```

### Template-Based Generator

```python
#!/usr/bin/env python3
# scripts/generate/template-generator.py

import yaml
import json
from jinja2 import Environment, FileSystemLoader, StrictUndefined
import argparse
import sys
from pathlib import Path

class TemplateGenerator:
    """Generate Kickstart files from Jinja2 templates."""
    
    def __init__(self, template_dir="templates"):
        self.env = Environment(
            loader=FileSystemLoader(template_dir),
            undefined=StrictUndefined,
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        # Add custom filters
        self.env.filters['to_yaml'] = self.to_yaml_filter
        self.env.filters['to_json'] = self.to_json_filter
    
    def to_yaml_filter(self, data):
        """Convert data to YAML format."""
        return yaml.dump(data, default_flow_style=False)
    
    def to_json_filter(self, data):
        """Convert data to JSON format."""
        return json.dumps(data, indent=2)
    
    def render_template(self, template_name, variables):
        """Render template with variables."""
        template = self.env.get_template(template_name)
        return template.render(**variables)
    
    def load_variables(self, var_file):
        """Load variables from YAML or JSON file."""
        with open(var_file, 'r') as f:
            if var_file.endswith('.json'):
                return json.load(f)
            else:
                return yaml.safe_load(f)

def main():
    parser = argparse.ArgumentParser(
        description='Generate Kickstart from templates'
    )
    parser.add_argument('template', help='Template file')
    parser.add_argument('--vars', required=True, help='Variables file')
    parser.add_argument('--output', '-o', help='Output file')
    
    args = parser.parse_args()
    
    generator = TemplateGenerator()
    variables = generator.load_variables(args.vars)
    output = generator.render_template(args.template, variables)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Generated {args.output}")
    else:
        print(output)

if __name__ == "__main__":
    main()
```

### Bulk Configuration Generator

```bash
#!/bin/bash
# scripts/generate/bulk-generator.sh

set -euo pipefail

# Generate multiple Kickstart files from CSV input
generate_bulk_configs() {
    local csv_file="$1"
    local template="$2"
    local output_dir="$3"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Skip header line and process CSV
    tail -n +2 "$csv_file" | while IFS=',' read -r hostname ip gateway username role; do
        echo "Generating config for $hostname..."
        
        # Create variables file
        cat > "/tmp/vars-$hostname.yaml" <<EOF
hostname: $hostname
ip_address: $ip
gateway: $gateway
username: $username
role: $role
EOF
        
        # Generate configuration
        python3 scripts/generate/template-generator.py \
            "$template" \
            --vars "/tmp/vars-$hostname.yaml" \
            --output "$output_dir/$hostname.yaml"
        
        # Cleanup
        rm -f "/tmp/vars-$hostname.yaml"
    done
}

# Example usage
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <csv_file> <template> <output_dir>"
    echo "CSV format: hostname,ip,gateway,username,role"
    exit 1
fi

generate_bulk_configs "$1" "$2" "$3"
```

## Validation Tools

### Comprehensive Validation Script

```python
#!/usr/bin/env python3
# scripts/validate/validate-kickstart.py

import yaml
import sys
import re
import ipaddress
import subprocess
from pathlib import Path
import jsonschema

class KickstartValidator:
    """Validate Ubuntu Kickstart configurations."""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
        
    def validate_file(self, filename):
        """Validate a Kickstart configuration file."""
        print(f"Validating {filename}...")
        
        # Load configuration
        try:
            with open(filename, 'r') as f:
                content = f.read()
                
            # Check cloud-config header
            if not content.startswith('#cloud-config'):
                self.errors.append("Missing #cloud-config header")
                
            # Parse YAML
            config = yaml.safe_load(content)
            
        except yaml.YAMLError as e:
            self.errors.append(f"YAML syntax error: {e}")
            return False
        except Exception as e:
            self.errors.append(f"Failed to read file: {e}")
            return False
        
        # Validate structure
        self.validate_structure(config)
        
        # Validate specific sections
        if 'autoinstall' in config:
            autoinstall = config['autoinstall']
            self.validate_version(autoinstall)
            self.validate_identity(autoinstall.get('identity', {}))
            self.validate_network(autoinstall.get('network', {}))
            self.validate_storage(autoinstall.get('storage', {}))
            self.validate_packages(autoinstall.get('packages', []))
            self.validate_ssh(autoinstall.get('ssh', {}))
            
        return len(self.errors) == 0
    
    def validate_structure(self, config):
        """Validate overall configuration structure."""
        if 'autoinstall' not in config:
            self.errors.append("Missing 'autoinstall' section")
            return
            
        if not isinstance(config['autoinstall'], dict):
            self.errors.append("'autoinstall' must be a dictionary")
    
    def validate_version(self, autoinstall):
        """Validate version specification."""
        if 'version' not in autoinstall:
            self.errors.append("Missing 'version' in autoinstall")
        elif autoinstall['version'] != 1:
            self.errors.append(f"Unsupported version: {autoinstall['version']}")
    
    def validate_identity(self, identity):
        """Validate identity configuration."""
        required_fields = ['hostname', 'username', 'password']
        
        for field in required_fields:
            if field not in identity:
                self.errors.append(f"Missing required field: identity.{field}")
        
        # Validate hostname
        if 'hostname' in identity:
            hostname = identity['hostname']
            if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$', hostname):
                self.errors.append(f"Invalid hostname: {hostname}")
        
        # Check for plaintext password
        if 'password' in identity:
            password = identity['password']
            if not password.startswith('$'):
                self.errors.append("Password appears to be plaintext (should be hashed)")
    
    def validate_network(self, network):
        """Validate network configuration."""
        if not network:
            self.warnings.append("No network configuration specified")
            return
            
        if 'version' not in network:
            self.errors.append("Network configuration missing 'version'")
        elif network['version'] != 2:
            self.errors.append(f"Unsupported network version: {network['version']}")
        
        # Validate ethernet interfaces
        if 'ethernets' in network:
            for iface, config in network['ethernets'].items():
                self.validate_interface(iface, config)
    
    def validate_interface(self, name, config):
        """Validate network interface configuration."""
        # Check for static IP configuration
        if 'addresses' in config:
            for addr in config['addresses']:
                try:
                    ipaddress.ip_interface(addr)
                except ValueError:
                    self.errors.append(f"Invalid IP address: {addr}")
        
        # Validate routes
        if 'routes' in config:
            for route in config['routes']:
                if 'via' in route:
                    try:
                        ipaddress.ip_address(route['via'])
                    except ValueError:
                        self.errors.append(f"Invalid gateway: {route['via']}")
    
    def validate_storage(self, storage):
        """Validate storage configuration."""
        if not storage:
            self.warnings.append("No storage configuration specified")
            return
            
        if 'layout' in storage:
            layout = storage['layout']
            if 'name' in layout:
                valid_layouts = ['lvm', 'direct', 'zfs']
                if layout['name'] not in valid_layouts:
                    self.errors.append(f"Invalid storage layout: {layout['name']}")
        
        if 'config' in storage:
            self.validate_storage_config(storage['config'])
    
    def validate_storage_config(self, config):
        """Validate detailed storage configuration."""
        disk_ids = set()
        partition_ids = set()
        
        for item in config:
            item_type = item.get('type')
            item_id = item.get('id')
            
            # Check for duplicate IDs
            if item_id:
                if item_type == 'disk' and item_id in disk_ids:
                    self.errors.append(f"Duplicate disk ID: {item_id}")
                elif item_type == 'partition' and item_id in partition_ids:
                    self.errors.append(f"Duplicate partition ID: {item_id}")
                
                if item_type == 'disk':
                    disk_ids.add(item_id)
                elif item_type == 'partition':
                    partition_ids.add(item_id)
    
    def validate_packages(self, packages):
        """Validate package list."""
        if not isinstance(packages, list):
            self.errors.append("Packages must be a list")
            return
            
        for pkg in packages:
            if not isinstance(pkg, str):
                self.errors.append(f"Invalid package specification: {pkg}")
    
    def validate_ssh(self, ssh):
        """Validate SSH configuration."""
        if not ssh:
            self.warnings.append("No SSH configuration specified")
            return
            
        if ssh.get('allow-pw', True):
            self.warnings.append("Password authentication is enabled for SSH")
        
        if 'authorized-keys' in ssh:
            for key in ssh['authorized-keys']:
                if not self.validate_ssh_key(key):
                    self.errors.append(f"Invalid SSH key format")
    
    def validate_ssh_key(self, key):
        """Validate SSH public key format."""
        ssh_key_pattern = re.compile(
            r'^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|'
            r'ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+/]+=*(\s+.*)?$'
        )
        return bool(ssh_key_pattern.match(key))
    
    def print_report(self):
        """Print validation report."""
        if self.errors:
            print("\nERRORS:")
            for error in self.errors:
                print(f"  ✗ {error}")
        
        if self.warnings:
            print("\nWARNINGS:")
            for warning in self.warnings:
                print(f"  ⚠ {warning}")
        
        if not self.errors and not self.warnings:
            print("✓ Configuration is valid")
        
        return len(self.errors) == 0

def main():
    if len(sys.argv) < 2:
        print("Usage: validate-kickstart.py <config_file>")
        sys.exit(1)
    
    validator = KickstartValidator()
    
    for filename in sys.argv[1:]:
        validator.errors = []
        validator.warnings = []
        
        if validator.validate_file(filename):
            print(f"✓ {filename} is valid")
        else:
            validator.print_report()
            sys.exit(1)

if __name__ == "__main__":
    main()
```

### Cloud-Init Schema Validator

```bash
#!/bin/bash
# scripts/validate/cloud-init-validator.sh

set -euo pipefail

validate_with_cloud_init() {
    local config_file="$1"
    
    echo "Validating with cloud-init schema..."
    
    # Check if cloud-init is installed
    if ! command -v cloud-init &> /dev/null; then
        echo "ERROR: cloud-init is not installed"
        exit 1
    fi
    
    # Validate schema
    if cloud-init devel schema --config-file "$config_file"; then
        echo "✓ Cloud-init schema validation passed"
    else
        echo "✗ Cloud-init schema validation failed"
        exit 1
    fi
    
    # Additional checks
    echo "Running additional validation checks..."
    
    # Check for security issues
    if grep -qE "password:\s*['\"]?[^$]" "$config_file"; then
        echo "✗ WARNING: Plaintext password detected"
    fi
    
    # Check for required sections
    if ! grep -q "identity:" "$config_file"; then
        echo "✗ ERROR: Missing identity section"
        exit 1
    fi
    
    echo "✓ All validation checks passed"
}

# Main
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <config_file>"
    exit 1
fi

validate_with_cloud_init "$1"
```

## Testing Frameworks

### Virtual Machine Test Framework

```python
#!/usr/bin/env python3
# scripts/test/vm-test-framework.py

import libvirt
import time
import paramiko
import subprocess
import tempfile
import os
from pathlib import Path

class VMTestFramework:
    """Framework for testing Kickstart configurations in VMs."""
    
    def __init__(self):
        self.conn = libvirt.open('qemu:///system')
        self.test_results = []
        
    def create_test_vm(self, name, kickstart_file, iso_path):
        """Create a test VM with Kickstart configuration."""
        
        # Create temporary disk
        disk_path = f"/var/lib/libvirt/images/{name}.qcow2"
        subprocess.run([
            'qemu-img', 'create', '-f', 'qcow2', disk_path, '20G'
        ], check=True)
        
        # Create cloud-init ISO
        ci_iso = self.create_cloudinit_iso(kickstart_file, name)
        
        # Define VM XML
        vm_xml = f"""
        <domain type='kvm'>
          <name>{name}</name>
          <memory unit='KiB'>2097152</memory>
          <vcpu placement='static'>2</vcpu>
          <os>
            <type arch='x86_64'>hvm</type>
            <boot dev='cdrom'/>
            <boot dev='hd'/>
          </os>
          <devices>
            <disk type='file' device='disk'>
              <driver name='qemu' type='qcow2'/>
              <source file='{disk_path}'/>
              <target dev='vda' bus='virtio'/>
            </disk>
            <disk type='file' device='cdrom'>
              <source file='{iso_path}'/>
              <target dev='sda' bus='sata'/>
              <readonly/>
            </disk>
            <disk type='file' device='cdrom'>
              <source file='{ci_iso}'/>
              <target dev='sdb' bus='sata'/>
              <readonly/>
            </disk>
            <interface type='network'>
              <source network='default'/>
              <model type='virtio'/>
            </interface>
            <console type='pty'>
              <target type='serial' port='0'/>
            </console>
            <graphics type='vnc' autoport='yes'/>
          </devices>
        </domain>
        """
        
        # Create and start VM
        dom = self.conn.createXML(vm_xml, 0)
        return dom
    
    def create_cloudinit_iso(self, kickstart_file, vm_name):
        """Create cloud-init ISO with Kickstart configuration."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Copy Kickstart file as user-data
            user_data = Path(tmpdir) / "user-data"
            user_data.write_text(Path(kickstart_file).read_text())
            
            # Create meta-data
            meta_data = Path(tmpdir) / "meta-data"
            meta_data.write_text(f"instance-id: {vm_name}\n")
            
            # Create ISO
            iso_path = f"/var/lib/libvirt/images/{vm_name}-cidata.iso"
            subprocess.run([
                'genisoimage', '-output', iso_path,
                '-volid', 'cidata', '-joliet', '-rock',
                str(tmpdir)
            ], check=True)
            
            return iso_path
    
    def wait_for_vm(self, domain, timeout=600):
        """Wait for VM to be accessible via SSH."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                # Get VM IP address
                ip = self.get_vm_ip(domain)
                if not ip:
                    time.sleep(10)
                    continue
                
                # Try SSH connection
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(ip, username='ubuntu', timeout=5)
                ssh.close()
                
                return ip
            except Exception:
                time.sleep(10)
        
        raise TimeoutError("VM did not become accessible")
    
    def get_vm_ip(self, domain):
        """Get IP address of VM."""
        # Implementation depends on network setup
        # This is a simplified version
        ifaces = domain.interfaceAddresses(
            libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE
        )
        
        for iface, addrs in ifaces.items():
            for addr in addrs.get('addrs', []):
                if addr['type'] == 0:  # IPv4
                    return addr['addr']
        
        return None
    
    def run_tests(self, vm_ip, test_suite):
        """Run test suite against VM."""
        results = []
        
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(vm_ip, username='ubuntu')
        
        for test in test_suite:
            try:
                stdin, stdout, stderr = ssh.exec_command(test['command'])
                output = stdout.read().decode()
                error = stderr.read().decode()
                exit_code = stdout.channel.recv_exit_status()
                
                results.append({
                    'name': test['name'],
                    'passed': exit_code == 0,
                    'output': output,
                    'error': error
                })
            except Exception as e:
                results.append({
                    'name': test['name'],
                    'passed': False,
                    'error': str(e)
                })
        
        ssh.close()
        return results

def main():
    """Run VM tests."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Test Kickstart configs')
    parser.add_argument('kickstart', help='Kickstart configuration file')
    parser.add_argument('--iso', required=True, help='Ubuntu ISO path')
    parser.add_argument('--name', default='test-vm', help='VM name')
    
    args = parser.parse_args()
    
    framework = VMTestFramework()
    
    # Define test suite
    test_suite = [
        {'name': 'SSH Access', 'command': 'echo "SSH working"'},
        {'name': 'Network', 'command': 'ip addr show'},
        {'name': 'Storage', 'command': 'df -h'},
        {'name': 'Packages', 'command': 'dpkg -l | grep nginx'},
        {'name': 'Services', 'command': 'systemctl status ssh'},
        {'name': 'Firewall', 'command': 'sudo ufw status'},
        {'name': 'Users', 'command': 'id ubuntu'},
    ]
    
    try:
        # Create and start VM
        print(f"Creating test VM: {args.name}")
        vm = framework.create_test_vm(args.name, args.kickstart, args.iso)
        
        # Wait for VM to be ready
        print("Waiting for VM to be accessible...")
        vm_ip = framework.wait_for_vm(vm)
        print(f"VM is ready at {vm_ip}")
        
        # Run tests
        print("Running test suite...")
        results = framework.run_tests(vm_ip, test_suite)
        
        # Print results
        print("\nTest Results:")
        print("-" * 50)
        for result in results:
            status = "PASS" if result['passed'] else "FAIL"
            print(f"{result['name']}: {status}")
            if not result['passed'] and 'error' in result:
                print(f"  Error: {result['error']}")
        
        # Cleanup
        vm.destroy()
        
    except Exception as e:
        print(f"Test failed: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
```

### Integration Test Suite

```bash
#!/bin/bash
# scripts/test/integration-tests.sh

set -euo pipefail

# Test configuration
TEST_ISO="${TEST_ISO:-ubuntu-22.04.3-live-server-amd64.iso}"
TEST_CONFIGS_DIR="${TEST_CONFIGS_DIR:-configs/test}"
RESULTS_DIR="${RESULTS_DIR:-test-results}"

# Create results directory
mkdir -p "$RESULTS_DIR"

run_integration_test() {
    local config_file="$1"
    local test_name=$(basename "$config_file" .yaml)
    local result_file="$RESULTS_DIR/${test_name}.log"
    
    echo "Running integration test: $test_name"
    
    # Create test VM
    local vm_name="test-${test_name}-$(date +%s)"
    
    # Deploy VM with configuration
    if scripts/test/vm-test-framework.py \
        "$config_file" \
        --iso "$TEST_ISO" \
        --name "$vm_name" > "$result_file" 2>&1; then
        echo "✓ $test_name: PASSED"
        return 0
    else
        echo "✗ $test_name: FAILED"
        echo "  See $result_file for details"
        return 1
    fi
}

# Run all test configurations
echo "Ubuntu Kickstart Integration Test Suite"
echo "======================================"
echo

total_tests=0
passed_tests=0

for config in "$TEST_CONFIGS_DIR"/*.yaml; do
    if [[ -f "$config" ]]; then
        ((total_tests++))
        if run_integration_test "$config"; then
            ((passed_tests++))
        fi
    fi
done

echo
echo "Test Summary:"
echo "============="
echo "Total tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $((total_tests - passed_tests))"

if [[ $passed_tests -eq $total_tests ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
```

## CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/kickstart-ci.yml
name: Kickstart CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * 1'  # Weekly validation

jobs:
  validate:
    name: Validate Configurations
    runs-on: ubuntu-22.04
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'
        
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y cloud-init
        pip install -r requirements.txt
        
    - name: Validate YAML syntax
      run: |
        find configs -name "*.yaml" -o -name "*.yml" | while read -r file; do
          echo "Validating $file"
          python -m yaml < "$file" > /dev/null
        done
        
    - name: Run Kickstart validator
      run: |
        find configs -name "*.yaml" | while read -r file; do
          python scripts/validate/validate-kickstart.py "$file"
        done
        
    - name: Cloud-init schema validation
      run: |
        find configs -name "*.yaml" | while read -r file; do
          cloud-init devel schema --config-file "$file"
        done
        
    - name: Security audit
      run: |
        scripts/audit/security-check.sh configs/

  test:
    name: Integration Tests
    runs-on: ubuntu-22.04
    needs: validate
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      
    - name: Set up test environment
      run: |
        sudo apt-get update
        sudo apt-get install -y qemu-kvm libvirt-daemon-system
        sudo usermod -aG libvirt $USER
        
    - name: Download test ISO
      run: |
        wget -q https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso
        
    - name: Run integration tests
      run: |
        sudo -E scripts/test/integration-tests.sh
        
    - name: Upload test results
      uses: actions/upload-artifact@v3
      with:
        name: test-results
        path: test-results/
        
  build:
    name: Build Deployment Artifacts
    runs-on: ubuntu-22.04
    needs: test
    if: github.ref == 'refs/heads/main'
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      
    - name: Generate deployment configs
      run: |
        scripts/generate/build-production-configs.sh
        
    - name: Create deployment package
      run: |
        tar czf kickstart-configs-${{ github.sha }}.tar.gz \
          configs/production/ \
          scripts/deploy/
          
    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: deployment-package
        path: kickstart-configs-*.tar.gz

  deploy:
    name: Deploy to Infrastructure
    runs-on: ubuntu-22.04
    needs: build
    if: github.ref == 'refs/heads/main'
    environment: production
    
    steps:
    - name: Download artifacts
      uses: actions/download-artifact@v3
      with:
        name: deployment-package
        
    - name: Deploy to configuration server
      env:
        DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
        DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
      run: |
        echo "$DEPLOY_KEY" > deploy_key
        chmod 600 deploy_key
        scp -i deploy_key kickstart-configs-*.tar.gz deploy@$DEPLOY_HOST:/srv/kickstart/
        ssh -i deploy_key deploy@$DEPLOY_HOST "cd /srv/kickstart && ./update-configs.sh"
```

### GitLab CI Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - test
  - build
  - deploy

variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"

cache:
  paths:
    - .cache/pip
    - venv/

before_script:
  - apt-get update -qq
  - apt-get install -y python3-pip python3-venv
  - python3 -m venv venv
  - source venv/bin/activate
  - pip install -r requirements.txt

validate:yaml:
  stage: validate
  script:
    - find configs -name "*.yaml" -exec python -m yaml {} \;
  only:
    - merge_requests
    - main
    - develop

validate:kickstart:
  stage: validate
  script:
    - |
      for config in configs/**/*.yaml; do
        python scripts/validate/validate-kickstart.py "$config"
      done
  only:
    - merge_requests
    - main
    - develop

validate:security:
  stage: validate
  script:
    - scripts/audit/security-check.sh configs/
  only:
    - merge_requests
    - main

test:unit:
  stage: test
  script:
    - pytest tests/unit/ -v --cov=scripts --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

test:integration:
  stage: test
  image: ubuntu:22.04
  services:
    - docker:dind
  script:
    - apt-get install -y qemu-kvm libvirt-daemon-system
    - scripts/test/integration-tests.sh
  artifacts:
    paths:
      - test-results/
    expire_in: 1 week

build:configs:
  stage: build
  script:
    - scripts/generate/build-production-configs.sh
    - tar czf kickstart-configs-${CI_COMMIT_SHA}.tar.gz configs/production/
  artifacts:
    paths:
      - kickstart-configs-*.tar.gz
    expire_in: 1 month
  only:
    - main

deploy:staging:
  stage: deploy
  script:
    - scripts/deploy/deploy-to-staging.sh
  environment:
    name: staging
    url: https://kickstart-staging.example.com
  only:
    - main

deploy:production:
  stage: deploy
  script:
    - scripts/deploy/deploy-to-production.sh
  environment:
    name: production
    url: https://kickstart.example.com
  when: manual
  only:
    - main
```

## Deployment Tools

### Automated Deployment Script

```python
#!/usr/bin/env python3
# scripts/deploy/auto-deploy.py

import os
import sys
import time
import yaml
import logging
import concurrent.futures
from pathlib import Path
import paramiko
import requests

class KickstartDeployer:
    """Deploy Ubuntu systems using Kickstart automation."""
    
    def __init__(self, config_file):
        with open(config_file, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.setup_logging()
        
    def setup_logging(self):
        """Configure logging."""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('deployment.log'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def deploy_system(self, target):
        """Deploy a single system."""
        self.logger.info(f"Deploying {target['hostname']}")
        
        try:
            # Generate Kickstart configuration
            kickstart_file = self.generate_kickstart(target)
            
            # Upload to deployment server
            self.upload_kickstart(kickstart_file, target)
            
            # Trigger installation
            self.trigger_installation(target)
            
            # Monitor progress
            self.monitor_installation(target)
            
            # Verify deployment
            self.verify_deployment(target)
            
            self.logger.info(f"Successfully deployed {target['hostname']}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to deploy {target['hostname']}: {e}")
            return False
    
    def generate_kickstart(self, target):
        """Generate Kickstart configuration for target."""
        template_file = f"templates/{target['role']}.yaml"
        
        # Load template
        with open(template_file, 'r') as f:
            template = yaml.safe_load(f)
        
        # Customize for target
        template['autoinstall']['identity']['hostname'] = target['hostname']
        template['autoinstall']['network']['ethernets'][target['interface']] = {
            'addresses': [f"{target['ip']}/{target['netmask']}"],
            'gateway4': target['gateway'],
            'nameservers': {'addresses': target['dns_servers']}
        }
        
        # Save customized configuration
        output_file = f"output/{target['hostname']}.yaml"
        with open(output_file, 'w') as f:
            yaml.dump(template, f)
        
        return output_file
    
    def trigger_installation(self, target):
        """Trigger PXE boot or other installation method."""
        if target['install_method'] == 'pxe':
            self.trigger_pxe_boot(target)
        elif target['install_method'] == 'ipmi':
            self.trigger_ipmi_boot(target)
        else:
            raise ValueError(f"Unknown install method: {target['install_method']}")
    
    def trigger_pxe_boot(self, target):
        """Configure PXE boot for target."""
        # Update DHCP configuration
        dhcp_entry = f"""
host {target['hostname']} {{
    hardware ethernet {target['mac_address']};
    fixed-address {target['ip']};
    next-server {self.config['pxe_server']};
    filename "pxelinux.0";
    option host-name "{target['hostname']}";
}}
"""
        
        # Add to DHCP configuration
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(
            self.config['dhcp_server'],
            username=self.config['dhcp_user'],
            key_filename=self.config['ssh_key']
        )
        
        stdin, stdout, stderr = ssh.exec_command(
            f"echo '{dhcp_entry}' | sudo tee -a /etc/dhcp/dhcpd.conf"
        )
        ssh.exec_command("sudo systemctl restart isc-dhcp-server")
        ssh.close()
    
    def monitor_installation(self, target):
        """Monitor installation progress."""
        start_time = time.time()
        timeout = self.config.get('install_timeout', 3600)  # 1 hour default
        
        while time.time() - start_time < timeout:
            if self.check_installation_complete(target):
                self.logger.info(f"{target['hostname']} installation complete")
                return True
            
            time.sleep(30)  # Check every 30 seconds
        
        raise TimeoutError(f"Installation timeout for {target['hostname']}")
    
    def check_installation_complete(self, target):
        """Check if installation is complete."""
        try:
            # Try SSH connection
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                target['ip'],
                username='ubuntu',
                timeout=5,
                key_filename=self.config['ssh_key']
            )
            ssh.close()
            return True
        except:
            return False
    
    def verify_deployment(self, target):
        """Verify successful deployment."""
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(
            target['ip'],
            username='ubuntu',
            key_filename=self.config['ssh_key']
        )
        
        # Run verification commands
        checks = [
            ('hostname', 'hostname'),
            ('network', 'ip addr show'),
            ('storage', 'df -h'),
            ('services', 'systemctl status ssh')
        ]
        
        for check_name, command in checks:
            stdin, stdout, stderr = ssh.exec_command(command)
            if stdout.channel.recv_exit_status() != 0:
                raise RuntimeError(f"Verification failed: {check_name}")
        
        ssh.close()
        self.logger.info(f"Verification passed for {target['hostname']}")
    
    def deploy_parallel(self, targets, max_workers=10):
        """Deploy multiple systems in parallel."""
        self.logger.info(f"Starting parallel deployment of {len(targets)} systems")
        
        results = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_target = {
                executor.submit(self.deploy_system, target): target 
                for target in targets
            }
            
            for future in concurrent.futures.as_completed(future_to_target):
                target = future_to_target[future]
                try:
                    result = future.result()
                    results.append((target['hostname'], result))
                except Exception as e:
                    self.logger.error(f"Exception for {target['hostname']}: {e}")
                    results.append((target['hostname'], False))
        
        # Summary
        successful = sum(1 for _, result in results if result)
        self.logger.info(f"Deployment complete: {successful}/{len(targets)} successful")
        
        return results

def main():
    """Main deployment function."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Deploy Ubuntu systems')
    parser.add_argument('config', help='Deployment configuration file')
    parser.add_argument('targets', help='Target systems file')
    parser.add_argument('--parallel', type=int, default=10,
                       help='Number of parallel deployments')
    
    args = parser.parse_args()
    
    # Load targets
    with open(args.targets, 'r') as f:
        targets = yaml.safe_load(f)['targets']
    
    # Deploy systems
    deployer = KickstartDeployer(args.config)
    results = deployer.deploy_parallel(targets, args.parallel)
    
    # Exit with error if any deployments failed
    if any(not result for _, result in results):
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### ISO Builder Tool

```bash
#!/bin/bash
# scripts/deploy/build-custom-iso.sh

set -euo pipefail

# Build custom Ubuntu ISO with embedded Kickstart
build_custom_iso() {
    local base_iso="$1"
    local kickstart_file="$2"
    local output_iso="$3"
    
    echo "Building custom ISO with Kickstart configuration..."
    
    # Create working directory
    WORK_DIR=$(mktemp -d)
    trap "rm -rf $WORK_DIR" EXIT
    
    # Extract ISO
    mkdir -p "$WORK_DIR/iso"
    7z x -o"$WORK_DIR/iso" "$base_iso" > /dev/null
    
    # Add Kickstart configuration
    mkdir -p "$WORK_DIR/iso/nocloud"
    cp "$kickstart_file" "$WORK_DIR/iso/nocloud/user-data"
    touch "$WORK_DIR/iso/nocloud/meta-data"
    
    # Update boot configuration
    update_boot_config "$WORK_DIR/iso"
    
    # Rebuild ISO
    cd "$WORK_DIR/iso"
    xorriso -as mkisofs \
        -r -V "Ubuntu Custom" \
        -o "$output_iso" \
        -J -l -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        .
    
    echo "Custom ISO created: $output_iso"
}

update_boot_config() {
    local iso_dir="$1"
    
    # Update GRUB configuration
    cat >> "$iso_dir/boot/grub/grub.cfg" <<EOF

menuentry "Automated Install" {
    set gfxpayload=keep
    linux   /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---
    initrd  /casper/initrd
}
EOF
    
    # Set as default boot option
    sed -i 's/timeout=30/timeout=10/' "$iso_dir/boot/grub/grub.cfg"
    sed -i 's/default=0/default=1/' "$iso_dir/boot/grub/grub.cfg"
}

# Main
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <base_iso> <kickstart_file> <output_iso>"
    exit 1
fi

# Check dependencies
for cmd in 7z xorriso; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd is required but not installed"
        exit 1
    fi
done

build_custom_iso "$1" "$2" "$3"
```

## Monitoring and Reporting

### Deployment Dashboard

```python
#!/usr/bin/env python3
# scripts/monitor/deployment-dashboard.py

from flask import Flask, render_template, jsonify
import sqlite3
import datetime
import json

app = Flask(__name__)

class DeploymentMonitor:
    """Monitor and report on Kickstart deployments."""
    
    def __init__(self, db_path="deployments.db"):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        """Initialize deployment database."""
        conn = sqlite3.connect(self.db_path)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS deployments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT NOT NULL,
                ip_address TEXT NOT NULL,
                status TEXT NOT NULL,
                start_time TIMESTAMP,
                end_time TIMESTAMP,
                duration INTEGER,
                kickstart_version TEXT,
                error_message TEXT,
                metadata TEXT
            )
        """)
        conn.commit()
        conn.close()
    
    def record_deployment(self, hostname, ip_address, status, **kwargs):
        """Record deployment information."""
        conn = sqlite3.connect(self.db_path)
        conn.execute("""
            INSERT INTO deployments 
            (hostname, ip_address, status, start_time, metadata)
            VALUES (?, ?, ?, ?, ?)
        """, (
            hostname, 
            ip_address, 
            status,
            datetime.datetime.now(),
            json.dumps(kwargs)
        ))
        conn.commit()
        conn.close()
    
    def get_deployment_stats(self):
        """Get deployment statistics."""
        conn = sqlite3.connect(self.db_path)
        
        # Overall stats
        stats = {}
        
        # Total deployments
        cursor = conn.execute("SELECT COUNT(*) FROM deployments")
        stats['total'] = cursor.fetchone()[0]
        
        # Success rate
        cursor = conn.execute("""
            SELECT 
                COUNT(CASE WHEN status = 'success' THEN 1 END) as success,
                COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed,
                COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress
            FROM deployments
        """)
        row = cursor.fetchone()
        stats['success'] = row[0]
        stats['failed'] = row[1]
        stats['in_progress'] = row[2]
        
        # Average deployment time
        cursor = conn.execute("""
            SELECT AVG(duration) 
            FROM deployments 
            WHERE status = 'success' AND duration IS NOT NULL
        """)
        stats['avg_duration'] = cursor.fetchone()[0] or 0
        
        conn.close()
        return stats
    
    def get_recent_deployments(self, limit=50):
        """Get recent deployment records."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute("""
            SELECT hostname, ip_address, status, start_time, duration, error_message
            FROM deployments
            ORDER BY start_time DESC
            LIMIT ?
        """, (limit,))
        
        deployments = []
        for row in cursor:
            deployments.append({
                'hostname': row[0],
                'ip_address': row[1],
                'status': row[2],
                'start_time': row[3],
                'duration': row[4],
                'error_message': row[5]
            })
        
        conn.close()
        return deployments

monitor = DeploymentMonitor()

@app.route('/')
def dashboard():
    """Main dashboard view."""
    return render_template('dashboard.html')

@app.route('/api/stats')
def get_stats():
    """API endpoint for deployment statistics."""
    return jsonify(monitor.get_deployment_stats())

@app.route('/api/deployments')
def get_deployments():
    """API endpoint for recent deployments."""
    return jsonify(monitor.get_recent_deployments())

@app.route('/api/record', methods=['POST'])
def record_deployment():
    """API endpoint to record deployment."""
    data = request.json
    monitor.record_deployment(
        data['hostname'],
        data['ip_address'],
        data['status'],
        **data.get('metadata', {})
    )
    return jsonify({'status': 'recorded'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
```

### Compliance Reporter

```python
#!/usr/bin/env python3
# scripts/monitor/compliance-reporter.py

import yaml
import json
import datetime
import subprocess
from pathlib import Path
import pandas as pd

class ComplianceReporter:
    """Generate compliance reports for Kickstart deployments."""
    
    def __init__(self, compliance_rules="compliance/rules.yaml"):
        with open(compliance_rules, 'r') as f:
            self.rules = yaml.safe_load(f)
    
    def check_system_compliance(self, hostname):
        """Check compliance of deployed system."""
        results = {
            'hostname': hostname,
            'timestamp': datetime.datetime.now().isoformat(),
            'checks': []
        }
        
        for rule in self.rules['rules']:
            check_result = self.run_compliance_check(hostname, rule)
            results['checks'].append(check_result)
        
        # Calculate overall compliance
        passed = sum(1 for check in results['checks'] if check['passed'])
        total = len(results['checks'])
        results['compliance_score'] = (passed / total * 100) if total > 0 else 0
        
        return results
    
    def run_compliance_check(self, hostname, rule):
        """Run individual compliance check."""
        result = {
            'rule_id': rule['id'],
            'description': rule['description'],
            'severity': rule['severity']
        }
        
        try:
            # Execute check command via SSH
            cmd = f"ssh ubuntu@{hostname} '{rule['command']}'"
            output = subprocess.check_output(
                cmd, 
                shell=True, 
                stderr=subprocess.STDOUT,
                timeout=30
            ).decode()
            
            # Evaluate result
            if rule['type'] == 'exact_match':
                result['passed'] = output.strip() == rule['expected']
            elif rule['type'] == 'contains':
                result['passed'] = rule['expected'] in output
            elif rule['type'] == 'regex':
                import re
                result['passed'] = bool(re.search(rule['expected'], output))
            else:
                result['passed'] = False
                
            result['output'] = output.strip()
            
        except subprocess.CalledProcessError as e:
            result['passed'] = False
            result['error'] = str(e)
        except Exception as e:
            result['passed'] = False
            result['error'] = str(e)
        
        return result
    
    def generate_report(self, results, format='html'):
        """Generate compliance report."""
        if format == 'html':
            return self.generate_html_report(results)
        elif format == 'json':
            return json.dumps(results, indent=2)
        elif format == 'csv':
            return self.generate_csv_report(results)
        else:
            raise ValueError(f"Unknown format: {format}")
    
    def generate_html_report(self, results):
        """Generate HTML compliance report."""
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Compliance Report - {results['hostname']}</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .header {{ background-color: #f0f0f0; padding: 10px; }}
                .passed {{ color: green; }}
                .failed {{ color: red; }}
                table {{ border-collapse: collapse; width: 100%; }}
                th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
                th {{ background-color: #4CAF50; color: white; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h1>Compliance Report</h1>
                <p>Host: {results['hostname']}</p>
                <p>Date: {results['timestamp']}</p>
                <p>Compliance Score: {results['compliance_score']:.1f}%</p>
            </div>
            
            <h2>Compliance Checks</h2>
            <table>
                <tr>
                    <th>Rule ID</th>
                    <th>Description</th>
                    <th>Severity</th>
                    <th>Status</th>
                    <th>Details</th>
                </tr>
        """
        
        for check in results['checks']:
            status_class = 'passed' if check['passed'] else 'failed'
            status_text = 'PASS' if check['passed'] else 'FAIL'
            
            html += f"""
                <tr>
                    <td>{check['rule_id']}</td>
                    <td>{check['description']}</td>
                    <td>{check['severity']}</td>
                    <td class="{status_class}">{status_text}</td>
                    <td>{check.get('error', check.get('output', ''))}</td>
                </tr>
            """
        
        html += """
            </table>
        </body>
        </html>
        """
        
        return html
    
    def batch_compliance_check(self, hostnames):
        """Run compliance checks on multiple systems."""
        all_results = []
        
        for hostname in hostnames:
            print(f"Checking compliance for {hostname}...")
            results = self.check_system_compliance(hostname)
            all_results.append(results)
        
        # Generate summary
        summary = {
            'total_systems': len(all_results),
            'average_compliance': sum(r['compliance_score'] for r in all_results) / len(all_results),
            'fully_compliant': sum(1 for r in all_results if r['compliance_score'] == 100),
            'non_compliant': sum(1 for r in all_results if r['compliance_score'] < 80)
        }
        
        return all_results, summary

def main():
    """Run compliance reporter."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Check deployment compliance')
    parser.add_argument('hostnames', nargs='+', help='Hostnames to check')
    parser.add_argument('--format', choices=['html', 'json', 'csv'], 
                       default='html', help='Output format')
    parser.add_argument('--output', help='Output file')
    
    args = parser.parse_args()
    
    reporter = ComplianceReporter()
    
    if len(args.hostnames) == 1:
        # Single system check
        results = reporter.check_system_compliance(args.hostnames[0])
        report = reporter.generate_report(results, args.format)
    else:
        # Multiple systems
        all_results, summary = reporter.batch_compliance_check(args.hostnames)
        report = reporter.generate_report({
            'summary': summary,
            'systems': all_results
        }, args.format)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(report)
        print(f"Report saved to {args.output}")
    else:
        print(report)

if __name__ == "__main__":
    main()
```

## Summary

This comprehensive suite of automation tools provides:

1. **Generation**: Interactive and template-based Kickstart file creation
2. **Validation**: Syntax checking, security auditing, and compliance verification
3. **Testing**: VM-based testing framework with integration test suites
4. **CI/CD**: Complete pipelines for GitHub Actions and GitLab CI
5. **Deployment**: Automated deployment tools with parallel execution
6. **Monitoring**: Real-time dashboards and compliance reporting

These tools enable efficient, reliable, and scalable Ubuntu system deployments using Kickstart automation.