#!/bin/bash

# Debug script to test config file creation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
DEFAULT_KERNEL_PATH="./vmlinux"
DEFAULT_ROOTFS_PATH="./rootfs.ext4"

# Create VM configuration for testing
test_create_vm_config() {
    local vm_id=1
    local vm_dir="vms/vm-$vm_id"
    local config_path="$vm_dir/config.json"
    local vm_rootfs="$vm_dir/rootfs.ext4"
    
    log_info "Testing config creation for VM $vm_id..."
    
    # Create directories
    mkdir -p "$vm_dir"
    
    # Check if vm_dir exists
    if [[ ! -d "$vm_dir" ]]; then
        log_error "VM directory does not exist: $vm_dir"
        return 1
    fi
    
    log_info "VM directory exists: $vm_dir"
    
    # Copy rootfs
    if [[ -f "$DEFAULT_ROOTFS_PATH" ]]; then
        cp "$DEFAULT_ROOTFS_PATH" "$vm_rootfs"
        log_info "Rootfs copied to: $vm_rootfs"
    else
        log_error "Base rootfs not found: $DEFAULT_ROOTFS_PATH"
        return 1
    fi
    
    # Create VM configuration
    log_info "Creating config file: $config_path"
    
    cat > "$config_path" << EOF
{
  "boot-source": {
    "kernel_image_path": "$(pwd)/$DEFAULT_KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$(pwd)/$vm_rootfs",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 128
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:01",
      "host_dev_name": "tap1"
    }
  ]
}
EOF
    
    # Verify config file was created
    if [[ ! -f "$config_path" ]]; then
        log_error "Failed to create config file: $config_path"
        return 1
    fi
    
    if [[ ! -s "$config_path" ]]; then
        log_error "Config file is empty: $config_path"
        return 1
    fi
    
    local line_count=$(wc -l < "$config_path")
    log_info "Config created successfully: $config_path ($line_count lines)"
    
    # Show file contents
    log_info "Config file contents:"
    cat "$config_path"
    
    echo "$config_path"
}

# Test kernel and rootfs paths
test_paths() {
    log_info "Testing asset paths..."
    
    if [[ -f "$DEFAULT_KERNEL_PATH" ]]; then
        log_info "Kernel found: $DEFAULT_KERNEL_PATH ($(stat -c%s "$DEFAULT_KERNEL_PATH") bytes)"
    else
        log_error "Kernel not found: $DEFAULT_KERNEL_PATH"
    fi
    
    if [[ -f "$DEFAULT_ROOTFS_PATH" ]]; then
        log_info "Rootfs found: $DEFAULT_ROOTFS_PATH ($(stat -c%s "$DEFAULT_ROOTFS_PATH") bytes)"
    else
        log_error "Rootfs not found: $DEFAULT_ROOTFS_PATH"
    fi
}

# Main test
main() {
    echo "🔧 Config Creation Debug Test"
    echo "============================="
    
    test_paths
    echo ""
    test_create_vm_config
    
    echo ""
    log_info "Test completed"
}

main "$@"