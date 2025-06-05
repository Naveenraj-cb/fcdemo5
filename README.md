# Firecracker Multi-VM Demo

This project demonstrates how to set up and run multiple Firecracker microVMs on Ubuntu. Firecracker is an open-source virtualization technology that creates lightweight virtual machines (microVMs) in milliseconds.

## What is Firecracker?

Firecracker is a Virtual Machine Monitor (VMM) that uses the Linux Kernel-based Virtual Machine (KVM) to create and manage microVMs. It was developed by AWS and is used to power AWS Lambda and AWS Fargate.

Key features:
- **Fast startup**: VMs boot in under 150ms
- **Lightweight**: Minimal memory overhead (~5MB per VM)
- **Secure**: Strong isolation between VMs
- **Simple**: RESTful API for VM management

## Prerequisites

### System Requirements
- Ubuntu 18.04+ (64-bit)
- CPU with virtualization support (Intel VT-x or AMD-V)
- At least 2GB RAM
- Virtualization enabled in BIOS

### Software Requirements
- KVM support
- curl, wget, jq (will be installed automatically if missing)

## Setup Instructions

### 1. Check System Compatibility

First, verify that your system supports KVM:

```bash
# Check if your CPU supports virtualization
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return a number > 0

# Check if KVM modules are available
lsmod | grep kvm
# Should show kvm_intel or kvm_amd

# If KVM modules are not loaded, load them:
sudo modprobe kvm_intel  # For Intel CPUs
# OR
sudo modprobe kvm_amd    # For AMD CPUs
```

### 2. Set User Permissions

Add your user to the kvm group:

```bash
sudo usermod -a -G kvm $USER
# Log out and log back in for changes to take effect
```

### 3. Clone and Setup

```bash
git clone <your-repo-url>
cd fc-demo-5
chmod +x script.sh
```

## Usage

### Starting VMs

Start 3 VMs (default):
```bash
./script.sh
```

Start a specific number of VMs:
```bash
./script.sh 5  # Start 5 VMs
```

### Managing VMs

Check VM status:
```bash
./script.sh status
```

Stop all VMs:
```bash
./script.sh stop
```

Restart all VMs:
```bash
./script.sh restart
```

Show help:
```bash
./script.sh help
```

## Project Structure

```
fc-demo-5/
├── script.sh           # Main script
├── README.md          # This file
├── bin/               # Firecracker binaries (created by script)
├── vms/               # VM configurations and data
│   ├── vm-1/
│   ├── vm-2/
│   └── vm-3/
├── logs/              # VM logs
├── sockets/           # API sockets for VM communication
├── vmlinux            # Linux kernel (downloaded automatically)
└── rootfs.ext4        # Root filesystem (downloaded automatically)
```

## What the Script Does

1. **Prerequisites Check**: Verifies system requirements and installs missing tools
2. **Firecracker Installation**: Downloads and installs Firecracker binaries locally
3. **Asset Download**: Downloads Linux kernel and root filesystem images
4. **Network Setup**: Creates TAP interfaces for VM networking
5. **VM Creation**: Configures and starts multiple Firecracker VMs
6. **Management**: Provides commands to start, stop, and monitor VMs

## VM Configuration

Each VM is configured with:
- **CPU**: 1 vCPU
- **Memory**: 128MB RAM
- **Network**: TAP interface with unique MAC address
- **Storage**: Individual ext4 root filesystem
- **Kernel**: Shared Linux kernel image

## Networking

- Each VM gets a TAP interface (`tap1`, `tap2`, etc.)
- VMs are on the `172.16.0.0/24` network
- Host acts as gateway at `172.16.0.1`
- NAT is configured for internet access

## Troubleshooting

### Common Issues

1. **KVM not accessible**:
   ```bash
   ls -la /dev/kvm
   # Should show: crw-rw---- 1 root kvm
   ```

2. **Permission denied on /dev/kvm**:
   ```bash
   sudo usermod -a -G kvm $USER
   # Then log out and log back in
   ```

3. **Firecracker fails to start**:
   - Check logs in `logs/firecracker-X.log`
   - Ensure no other process is using the socket
   - Verify VM configuration in `vms/vm-X/config.json`

4. **Network issues**:
   ```bash
   # Check TAP interfaces
   ip link show | grep tap
   
   # Check iptables rules
   sudo iptables -t nat -L
   ```

### Useful Commands

Monitor VM processes:
```bash
ps aux | grep firecracker
```

Check VM logs:
```bash
tail -f logs/firecracker-1.log
```

Test VM connectivity (once running):
```bash
ping 172.16.0.2  # VM 1
ping 172.16.0.3  # VM 2
```

## Next Steps

This is Part 1 of a 3-part demo:
- **Part 1**: ✅ Spin up 3 Firecracker VMs
- **Part 2**: Install Deno programs in each VM
- **Part 3**: HTTP communication between host and VMs

## Resources

- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [Firecracker API Reference](https://github.com/firecracker-microvm/firecracker/blob/main/src/api_server/swagger/firecracker.yaml)
- [AWS Firecracker](https://firecracker-microvm.github.io/)

## License

This project is for educational purposes. Firecracker is licensed under Apache 2.0.