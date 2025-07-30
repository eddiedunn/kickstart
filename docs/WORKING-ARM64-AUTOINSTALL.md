# Working Ubuntu 22.04 ARM64 Autoinstall for Parallels Desktop

This document describes the working configuration for Ubuntu 22.04 ARM64 autoinstall on Parallels Desktop (Apple Silicon).

## Key Issues Resolved

1. **ARM64 GRUB Syntax**: The semicolon in `ds=nocloud;s=/cdrom/nocloud/` must be escaped as `ds=nocloud\;s=/cdrom/nocloud/`
2. **GRUB Timeout**: Increased from 1 to 3 seconds to allow intervention if needed
3. **SSH Configuration**: Keep SSH configuration simple - avoid complex late-commands
4. **Package Selection**: Some packages like `linux-cloud-tools-generic` are not available for ARM64

## Working Build Script

The minimal working build script (`scripts/build-minimal-autoinstall.sh`) creates an ISO with:

```yaml
#cloud-config
autoinstall:
  version: 1
  
  locale: en_US.UTF-8
  keyboard:
    layout: us
  
  network:
    version: 2
    ethernets:
      enp0s5:
        dhcp4: true
  
  storage:
    layout:
      name: lvm
  
  identity:
    hostname: ubuntu-server
    username: ubuntu
    password: "$6$rounds=4096$8dkK1P/oE$2DGKKt0wLlTVJ7USY.0jN9du8FetmEr51yjPyeiR.zKE3DGFcitNL/nF1l62BLJNR87lQZixObuXYny.Mf17K1"
  
  ssh:
    install-server: true
    authorized-keys:
      - "your-ssh-public-key-here"
  
  packages:
    - qemu-guest-agent
    - openssh-server
    - curl
    - vim
  
  shutdown: reboot
```

## Building the ISO

```bash
# Build the autoinstall ISO
./scripts/build-minimal-autoinstall.sh ubuntu-22.04.5-live-server-arm64.iso
```

## Deploying the VM

```bash
# Deploy VM directly without Terraform
./scripts/test-minimal-iso.sh
```

Or manually:

```bash
# Create VM
prlctl create ubuntu-test --distribution ubuntu --no-hdd

# Configure VM
prlctl set ubuntu-test \
  --cpus 2 \
  --memsize 4096 \
  --efi-boot on \
  --device-add hdd --size 20480

# Attach ISO
prlctl set ubuntu-test \
  --device-set cdrom0 \
  --image /path/to/autoinstall.iso \
  --connect

# Set boot order
prlctl set ubuntu-test --device-bootorder "cdrom0 hdd0"

# Start VM
prlctl start ubuntu-test
```

## Verification

After about 5-10 minutes, the VM will complete installation and reboot. You can then:

1. Check VM IP:
   ```bash
   prlctl list -i ubuntu-test | grep IP
   ```

2. SSH to the VM:
   ```bash
   ssh ubuntu@<vm-ip>
   ```

## Important Notes

- The default password is 'ubuntu' but SSH password auth is disabled
- Only SSH key authentication is allowed
- The VM uses DHCP on the default Parallels network (10.211.55.0/24)
- Installation takes approximately 5-10 minutes depending on hardware

## Troubleshooting

If the autoinstall doesn't trigger:
1. Check that the GRUB timeout is visible (3 seconds)
2. Verify the kernel command line includes `autoinstall ds=nocloud\;s=/cdrom/nocloud/`
3. Ensure the ISO was built for the correct architecture (ARM64 for Apple Silicon)

## Files Created

- `/scripts/build-minimal-autoinstall.sh` - Minimal ISO builder that works
- `/scripts/test-minimal-iso.sh` - Test deployment script
- `/output/ubuntu-minimal-autoinstall-*.iso` - Generated ISO files