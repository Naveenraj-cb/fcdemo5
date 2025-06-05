# Firecracker Multi-VM Demo

This project demonstrates how to set up and run multiple Firecracker microVMs on Ubuntu. This is Part 1 of a 3-part demo series that will eventually include Deno applications and HTTP communication.

## What is Firecracker?

Firecracker is an open-source Virtual Machine Monitor (VMM) that uses the Linux Kernel-based Virtual Machine (KVM) to create and manage lightweight microVMs. It was developed by AWS and powers AWS Lambda and AWS Fargate.

### Key Features:
- **Lightning fast**: VMs boot in under 150ms
- **Lightweight**: ~5MB memory overhead per VM
- **Secure**: Strong workload isolation
- **Simple**: RESTful API for management
- **Scalable**: Thousands of VMs per host

## Prerequisites

### System Requirements
- **OS**: Ubuntu 18.04+ (64-bit) or compatible Linux distribution
- **CPU**: Intel VT-x or AMD-V virtualization support
- **Memory**: At least 2GB RAM (4GB+ recommended)
- **Storage**: 1GB free space for VM images
- **Virtualization**: Must be enabled in BIOS/UEFI

### Verification Commands

Check CPU virtualization support:
```bash
# Should return > 0
egrep -c '(vmx|svm)' /proc/cpuinfo

# Check virtualization flags
lscpu | grep Virtualization
```

Check KVM availability:
```bash
# Should show kvm device
ls -la /dev/kvm

# Load KVM modules if needed
sudo modprobe kvm_intel  # Intel CPUs
# OR
sudo modprobe kvm_amd    # AMD CPUs

# Verify modules are loaded
lsmod | grep kvm
```

## Quick Start

### Option 1: Fast Setup (Recommended)
```bash
# Use the optimized script that skips downloads if files exist
chmod +x script-optimized.sh

# Start 3 VMs (first run will download assets)
./script-optimized.sh

# Subsequent runs are much faster (skips downloads)
./script-optimized.sh
```

### Option 2: Original Script
```bash
# Use the original script
chmod +x script.sh

# Start 3 VMs
./script.sh
```

### 1. Setup User Permissions
```bash
# Add user to kvm group (required for KVM access)
sudo usermod -a -G kvm $USER

# Log out and log back in, or use:
newgrp kvm
```

### 2. Run the Demo
```bash
# Start 3 VMs (default) - optimized version
./script-optimized.sh

# Or specify number of VMs
./script-optimized.sh 5
```

### 3. Check Status
```bash
# Check if VMs are running
./script-optimized.sh status

# View VM logs (helpful for troubleshooting)
tail -f logs/firecracker-1.log
tail logs/firecracker-*.log  # View all VM logs

# Check processes
ps aux | grep firecracker
```

### 4. Stop VMs
```bash
./script-optimized.sh stop
```

### 5. Common Workflow
```bash
# Complete workflow example
./script-optimized.sh 3         # Start 3 VMs
./script-optimized.sh status     # Check they're running
./script-optimized.sh stop       # Stop when done

# Quick restart
./script-optimized.sh restart    # Stop and start again
```

## Script Commands

| Command | Description | Example |
|---------|-------------|---------|
| `start` | Start VMs (default) | `./script-optimized.sh` or `./script-optimized.sh 5` |
| `stop` | Stop all VMs | `./script-optimized.sh stop` |
| `status` | Check VM status | `./script-optimized.sh status` |
| `restart` | Restart all VMs | `./script-optimized.sh restart` |
| `clean` | Clean all assets and start fresh | `./script-optimized.sh clean` |

### Optimized Script Features

The `script-optimized.sh` includes several performance improvements:

- **Smart Downloads**: Skips downloads if valid files already exist
- **Asset Verification**: Checks file integrity before use
- **Network Optimization**: Reuses existing TAP interfaces when possible
- **Better Logging**: Color-coded output with skip indicators
- **Fast Restarts**: Subsequent runs are 5-10x faster
- **Progress Indicators**: Shows download progress
- **Error Recovery**: Better error messages and recovery suggestions

## What the Script Does

### Automatic Setup
1. **Dependency Check**: Installs curl, wget, jq if missing
2. **Firecracker Installation**: Downloads v1.4.1 binaries automatically
3. **Asset Download**: Gets Linux kernel and rootfs images
4. **Directory Structure**: Creates organized folder structure
5. **Network Configuration**: Sets up TAP interfaces and routing

### VM Configuration
Each VM is configured with:
- **CPU**: 1 vCPU
- **Memory**: 128MB RAM
- **Network**: Unique TAP interface with MAC address
- **Storage**: Individual ext4 root filesystem (50MB)
- **Kernel**: Shared Linux kernel image

### Network Architecture
```
Host (172.16.0.1)
├── VM1 (172.16.0.2) - tap1
├── VM2 (172.16.0.3) - tap2
└── VM3 (172.16.0.4) - tap3
```

## Project Structure

```
fc-demo-5/
├── script.sh              # Main orchestration script
├── script-optimized.sh    # Optimized version (recommended)
├── troubleshoot.sh        # Diagnostic and repair script
├── README.md              # This documentation
├── bin/                   # Firecracker binaries (auto-created)
│   ├── firecracker        # Main VMM binary
│   └── jailer             # Security sandbox tool
├── vms/                   # VM instances (auto-created)
│   ├── vm-1/
│   │   ├── config.json    # VM configuration
│   │   ├── rootfs.ext4    # Individual filesystem
│   │   └── firecracker.pid # Process ID file
│   ├── vm-2/
│   └── vm-3/
├── logs/                  # VM output logs (auto-created)
│   ├── firecracker-1.log
│   ├── firecracker-2.log
│   └── firecracker-3.log
├── sockets/               # API communication (auto-created)
│   ├── firecracker-1.socket
│   ├── firecracker-2.socket
│   └── firecracker-3.socket
├── vmlinux                # Linux kernel (auto-downloaded)
└── rootfs.ext4            # Base root filesystem (auto-downloaded)
```

## VM Management

### Monitoring VMs
```bash
# Check all VM processes
ps aux | grep firecracker

# Monitor system resources
htop

# Check network interfaces
ip link show | grep tap

# View VM configurations
cat vms/vm-1/config.json | jq .
```

### Individual VM Control
```bash
# Start specific VM manually
./bin/firecracker --api-sock sockets/firecracker-1.socket --config-file vms/vm-1/config.json

# Check VM via API
curl --unix-socket sockets/firecracker-1.socket \
     -X GET http://localhost/

# Get VM info
curl --unix-socket sockets/firecracker-1.socket \
     -X GET http://localhost/machine-config
```

## Troubleshooting

### Quick Fix for Kernel Loading Issues

If you're getting `KernelLoader(Elf(ReadElfHeader))` errors:

```bash
# Run the troubleshooting script
chmod +x troubleshoot.sh
./troubleshoot.sh fix

# Or manually clean and retry
./script.sh clean
./script.sh
```

### Common Issues

#### 1. Permission Denied on /dev/kvm
```bash
# Check current permissions
ls -la /dev/kvm

# Should show: crw-rw---- 1 root kvm

# Fix: Add user to kvm group
sudo usermod -a -G kvm $USER
# Then logout/login
```

#### 2. Firecracker Won't Start - Kernel Loading Error
```bash
# Check if kernel file is corrupted
file vmlinux
# Should show: ELF 64-bit LSB executable

# If corrupted, clean and re-download
./script.sh clean
./script.sh

# Or use troubleshooting script
./troubleshoot.sh check
```

#### 3. Network Issues
```bash
# Check TAP interfaces
ip addr show | grep tap

# Verify IP forwarding
cat /proc/sys/net/ipv4/ip_forward
# Should show: 1

# Check iptables rules
sudo iptables -t nat -L POSTROUTING
sudo iptables -L FORWARD
```

#### 4. VM Boot Failures
```bash
# Check VM configuration
jq . vms/vm-1/config.json

# Verify kernel and rootfs exist
ls -la vmlinux rootfs.ext4

# Check boot args in logs
grep "boot_args" logs/firecracker-1.log
```

### Troubleshooting Tools

Use the troubleshooting script for detailed diagnostics:

```bash
# Check system and assets
./troubleshoot.sh check

# Download fresh assets
./troubleshoot.sh download

# Run comprehensive fix
./troubleshoot.sh fix
```

### Reset Everything
```bash
# Stop all VMs and clean up
./script.sh stop

# Remove all generated files
rm -rf bin/ vms/ logs/ sockets/ vmlinux rootfs.ext4

# Start fresh
./script.sh
```

## Advanced Usage

### Custom Kernel/Rootfs
```bash
# Use custom kernel
KERNEL_PATH="/path/to/custom/vmlinux" ./script.sh

# Use custom rootfs
ROOTFS_PATH="/path/to/custom/rootfs.ext4" ./script.sh
```

### Resource Customization
Edit the script to modify:
- `mem_size_mib`: VM memory (currently 128MB)
- `vcpu_count`: CPU cores (currently 1)
- Network configuration
- Storage size

## Demo Series Roadmap

- **Part 1**: ✅ Multi-VM Firecracker Setup
- **Part 2**: 🔄 Deno Applications in VMs
- **Part 3**: 🔄 HTTP Communication & Load Balancing

## Performance Notes

### Resource Usage (per VM)
- **Memory**: ~133MB (128MB + overhead)
- **CPU**: Minimal when idle
- **Storage**: ~50MB per VM
- **Boot time**: ~150ms

### Scaling Considerations
- Test system can handle 10-20 VMs comfortably
- Production setups can run 1000+ VMs per host
- Memory is the primary constraint
- Network TAP interfaces have kernel limits

## References

- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [Firecracker API Specification](https://github.com/firecracker-microvm/firecracker/blob/main/src/api_server/swagger/firecracker.yaml)
- [AWS Firecracker Homepage](https://firecracker-microvm.github.io/)
- [KVM Documentation](https://www.linux-kvm.org/)

## Contributing

This is an educational project. Feel free to:
- Report issues
- Suggest improvements
- Add new features
- Create additional demo parts

## License

Educational use. Firecracker is Apache 2.0 licensed.

---

**Next**: Once Part 1 is working, we'll add Deno applications to each VM in Part 2!