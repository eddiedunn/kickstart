# ISO-Based Installation Quick Start

Deploy Ubuntu VMs from scratch using custom autoinstall ISOs.

## Prerequisites

- Ubuntu Server ISO (22.04 or later)
- macOS with Parallels Desktop
- OpenTofu/Terraform installed

## 1. Build Custom ISO (2 minutes)

```bash
# Build ISO with embedded SSH keys
./scripts/build-autoinstall-iso.sh /path/to/ubuntu-22.04.5-live-server-arm64.iso

# Script will:
# - Auto-detect ISO version
# - Let you select SSH keys from ~/.ssh/
# - Create ISO in output/ directory
```

## 2. Deploy VM (15-20 minutes)

```bash
cd opentofu

# Configure deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set iso_path to your new ISO

# Deploy
tofu init
tofu apply
```

## 3. Connect to VM

```bash
# Get IP address
./scripts/status.sh

# SSH in (password-less with your keys)
ssh ubuntu@<ip-address>
```

## What You Get

- ✅ Ubuntu Server (latest)
- ✅ LVM storage layout
- ✅ SSH server (keys only)
- ✅ Basic tools installed
- ✅ Ready for customization

## Next Steps

- **Multiple VMs?** See [Deployment Methods](deployment-methods.md)
- **Need templates?** Deploy once, then convert to template
- **Customization?** Edit autoinstall config before building ISO

## Common Issues

**VM won't boot?**
- Ensure using EFI firmware for ARM64
- Check ISO path in terraform.tfvars

**No IP address?**
- Wait for installation to complete
- Use `./scripts/status.sh --watch`

**SSH fails?**
- Verify your SSH key was selected during ISO build
- Check VM is fully booted