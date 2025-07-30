# Ubuntu VM Automation Hub

**Deploy Ubuntu VMs in seconds, not minutes!** This repository provides battle-tested VM templates and automation tools for Parallels Desktop. Perfect for development environments, testing, and proof-of-concepts.

## 🚀 Quick Start - Deploy VMs in Under 5 Minutes

**Most users want this:** Deploy VMs from pre-built templates in seconds.

```bash
# 1. Clone this repo
git clone https://github.com/eddiedunn/kickstart.git && cd kickstart

# 2. Deploy VMs (uses template method by default)
cd opentofu
cp terraform.tfvars.template-example terraform.tfvars
# Add your SSH key to terraform.tfvars
tofu init && tofu apply
```

**That's it!** You now have multiple VMs running. See [Template Quick Start](docs/TEMPLATE-QUICKSTART.md) for the complete 5-minute guide.

## Overview

### Why Use Templates?

- **⚡ Lightning Fast**: Deploy VMs in seconds instead of 15-20 minutes
- **💾 Space Efficient**: Linked clones use 90% less disk space  
- **🔄 Consistent**: Every VM starts from the same validated base
- **🛠️ Pre-configured**: Common tools already installed and configured

### Deployment Methods Available

1. **Template-based Cloning** (Recommended) - Deploy VMs in seconds from pre-configured templates
2. **ISO-based Autoinstall** (Advanced) - Build VMs from scratch when you need fresh installs
3. **Cloud-Init Integration** - Customize VMs on first boot (works with both methods)

### Perfect For

- **Development Teams**: Spin up consistent dev environments instantly
- **Testing & QA**: Deploy test environments in seconds, destroy when done
- **POCs & Demos**: Quickly create multi-VM environments for demonstrations
- **Learning**: Practice Kubernetes, distributed systems, etc. with real VMs
- **CI/CD**: Automated VM provisioning for testing pipelines

### Key Features

- **Multi-Architecture Support**: Optimized for ARM64 (Apple Silicon) and AMD64
- **Parallels Desktop Integration**: Native support for macOS virtualization
- **OpenTofu/Terraform**: Declarative VM management
- **Automated ISO Building**: Create custom Ubuntu ISOs with autoinstall
- **Template Management**: Tools for creating and managing VM templates
- **Cloud-Init Support**: Dynamic VM customization

## Repository Structure

```
kickstart/
├── README.md                     # This file
├── CLAUDE.md                    # AI assistant guidance
├── docs/                        # Documentation
│   ├── TEMPLATE-QUICKSTART.md   # ⭐ START HERE - 5-minute guide
│   ├── TEMPLATE-MAINTENANCE.md  # Keep templates updated
│   ├── VM-TEMPLATE-GUIDE.md     # Advanced template management
│   ├── ISO-QUICKSTART.md        # ISO-based deployment (advanced)
│   └── *.md                     # Additional guides
├── opentofu/                    # Infrastructure as Code
│   ├── main.tf                  # ISO-based deployments
│   ├── main-templates.tf        # Template-based deployments
│   ├── modules/                 # Reusable modules
│   ├── cloud-init-examples/     # Cloud-init templates
│   └── terraform.tfvars.*       # Example configurations
├── scripts/                     # Automation scripts
│   ├── build-autoinstall-iso.sh # ISO builder
│   ├── create-parallels-template.sh # Template creator
│   ├── manage-templates.sh      # Template management
│   ├── prepare-vm-template.sh   # VM preparation
│   └── deploy-vm.sh            # Deployment helper
├── configs/                     # Kickstart/Autoinstall configs
│   ├── ubuntu-22.04-handsfree.yaml # Autoinstall config
│   └── cloud-init-template.yaml # Cloud-init template
├── autoinstall/                 # Autoinstall files
│   ├── user-data               # Ubuntu autoinstall config
│   └── meta-data               # Instance metadata
└── output/                      # Generated ISOs
```

## Getting Started

### 🎯 For Most Users: Template-Based Deployment

**Deploy VMs in seconds using pre-built templates:**

1. **[Template Quick Start](docs/TEMPLATE-QUICKSTART.md)** - 5-minute guide to deploying VMs
2. **[Template Maintenance](docs/TEMPLATE-MAINTENANCE.md)** - Keep templates updated with patches
3. **[Advanced Template Guide](docs/VM-TEMPLATE-GUIDE.md)** - Create custom templates

### 🔧 For Advanced Users: ISO-Based Deployment

**Build VMs from scratch when you need:**
- Fresh installs with latest Ubuntu version
- Custom partition layouts
- Compliance-specific configurations
- CI/CD pipeline integration

See [ISO Quick Start](docs/ISO-QUICKSTART.md) for instructions.

### 📊 Comparison

| Method | Deploy Time | Use Case | Difficulty |
|--------|------------|----------|------------|
| **Templates** | < 1 minute | Development, Testing, POCs | Easy |
| **ISO** | 15-20 minutes | Production, Fresh Installs | Advanced |

## Supported Ubuntu Versions

- Ubuntu 24.04 LTS (Noble Numbat)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 20.04 LTS (Focal Fossa)

## Prerequisites

- Ubuntu 20.04+ host system for running tools
- Python 3.8+ for automation scripts
- cloud-init (for cloud deployments)
- xorriso (for ISO generation)
- QEMU/KVM (for testing)

## Documentation

### 🚀 Start Here
- **[Template Quick Start](docs/TEMPLATE-QUICKSTART.md)** - Deploy VMs in 5 minutes
- **[ISO Quick Start](docs/ISO-QUICKSTART.md)** - Build VMs from scratch

### 📚 Comprehensive Guides

**Deployment & Configuration**
- [Deployment Methods](docs/deployment-methods.md) - All deployment options compared
- [Template Guide](docs/VM-TEMPLATE-GUIDE.md) - Create and manage VM templates
- [Template Maintenance](docs/TEMPLATE-MAINTENANCE.md) - Keep templates updated

**Reference & Troubleshooting**
- [Technical Reference](docs/technical-reference.md) - In-depth technical details
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions

## Available Tools

### Core Scripts
- **build-autoinstall-iso.sh** - Build custom Ubuntu ISOs with autoinstall
- **create-parallels-template.sh** - Create VM templates from existing VMs
- **manage-templates.sh** - Comprehensive template management utility
- **deploy-vm.sh** - Deploy VMs from ISOs or templates

### OpenTofu/Terraform Modules
- **parallels-vm** - Core module for VM provisioning
- **vm-template** - Module for template-based deployments

## Best Practices

### Security
- Store passwords as SHA-512 hashes, never plaintext
- Use SSH keys for authentication
- Enable firewall and fail2ban
- Regular security updates via unattended-upgrades

### Template Management
- Version your templates (e.g., ubuntu-22.04-v1.2.0)
- Document template contents and changes
- Test templates before production use
- Regular monthly updates for security patches

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/eddiedunn/kickstart/issues)
- **Discussions**: [GitHub Discussions](https://github.com/eddiedunn/kickstart/discussions)
- **Security**: For security issues, please email security@example.com

## Acknowledgments

- Ubuntu Server Team for Subiquity installer enhancements
- The cloud-init project for seamless cloud integration
- The open-source community for continuous improvements