#!/bin/bash

# Troubleshooting script for Firecracker issues
# This script helps debug common problems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check downloaded assets
check_assets() {
    echo "=========================================="
    echo "   Checking Downloaded Assets"
    echo "=========================================="
    
    if [[ -f "vmlinux" ]]; then
        log_debug "Kernel file exists"
        log_debug "Size: $(stat -c%s vmlinux) bytes"
        log_debug "Type: $(file vmlinux)"
        
        # Check if it's a valid ELF file
        if file vmlinux | grep -q "ELF"; then
            log_info "Kernel file appears to be a valid ELF binary"
        else
            log_error "Kernel file is NOT a valid ELF binary"
            log_warn "Recommendation: Run './script.sh clean' and try again"
        fi
        
        # Check readability
        if [[ -r "vmlinux" ]]; then
            log_info "Kernel file is readable"
        else
            log_error "Kernel file is not readable"
        fi
        
        # Check if it looks like HTML (common issue)
        if head -n 1 vmlinux | grep -q "<"; then
            log_error "Kernel file appears to be HTML (download failed)"
            log_warn "This usually means the download URL is redirecting"
        fi
        
    else
        log_warn "Kernel file (vmlinux) not found"
    fi
    
    if [[ -f "rootfs.ext4" ]]; then
        log_debug "Rootfs file exists"
        log_debug "Size: $(stat -c%s rootfs.ext4) bytes"
        log_debug "Type: $(file rootfs.ext4)"
        
        if file rootfs.ext4 | grep -q "ext.*filesystem"; then
            log_info "Rootfs file appears to be a valid ext4 filesystem"
        else
            log_error "Rootfs file is NOT a valid ext4 filesystem"
        fi
    else
        log_warn "Rootfs file (rootfs.ext4) not found"
    fi
}

# Check system prerequisites
check_system() {
    echo "=========================================="
    echo "   Checking System Prerequisites"
    echo "=========================================="
    
    # Check KVM
    if [[ -c "/dev/kvm" ]]; then
        log_info "KVM device exists"
        ls -la /dev/kvm
        
        # Check permissions
        if [[ -r "/dev/kvm" && -w "/dev/kvm" ]]; then
            log_info "KVM device is accessible"
        else
            log_error "KVM device permissions issue"
            log_warn "Run: sudo usermod -a -G kvm $USER"
            log_warn "Then log out and log back in"
        fi
    else
        log_error "KVM device not found"
        log_warn "Check if KVM modules are loaded: lsmod | grep kvm"
    fi
    
    # Check CPU virtualization
    if egrep -q '(vmx|svm)' /proc/cpuinfo; then
        log_info "CPU virtualization support detected"
    else
        log_error "CPU virtualization not supported or not enabled"
    fi
    
    # Check Firecracker
    if [[ -x "./bin/firecracker" ]]; then
        log_info "Firecracker binary found locally"
        ./bin/firecracker --version | head -1
    elif command -v firecracker &> /dev/null; then
        log_info "Firecracker found in system PATH"
        firecracker --version | head -1
    else
        log_error "Firecracker not found"
    fi
}

# Test kernel loading
test_kernel_loading() {
    echo "=========================================="
    echo "   Testing Kernel Loading"
    echo "=========================================="
    
    if [[ ! -f "vmlinux" ]]; then
        log_error "No kernel file to test"
        return
    fi
    
    # Try to create a minimal config to test kernel loading
    local test_config="test_config.json"
    cat > "$test_config" << EOF
{
  "boot-source": {
    "kernel_image_path": "$(pwd)/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 128
  }
}
EOF
    
    log_info "Testing kernel loading with minimal config..."
    
    # Try to start firecracker with this config
    if timeout 5 ./bin/firecracker --api-sock /tmp/test.socket --config-file "$test_config" 2>&1 | grep -q "KernelLoader"; then
        log_error "Kernel loading failed - likely corrupted kernel file"
    else
        log_info "Kernel loading test passed"
    fi
    
    # Clean up
    rm -f "$test_config" /tmp/test.socket
}

# Download fresh assets
download_fresh_assets() {
    echo "=========================================="
    echo "   Downloading Fresh Assets"
    echo "=========================================="
    
    log_info "Cleaning old assets..."
    rm -f vmlinux rootfs.ext4
    
    log_info "Downloading kernel from AWS S3..."
    if wget -O vmlinux.tmp "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin"; then
        if file vmlinux.tmp | grep -q "ELF"; then
            mv vmlinux.tmp vmlinux
            log_info "Kernel downloaded successfully"
        else
            log_error "Downloaded kernel is not valid ELF"
            rm -f vmlinux.tmp
        fi
    else
        log_error "Failed to download kernel"
    fi
    
    log_info "Downloading rootfs from AWS S3..."
    if wget -O rootfs.ext4.tmp "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/rootfs/bionic.rootfs.ext4"; then
        if file rootfs.ext4.tmp | grep -q "ext.*filesystem"; then
            mv rootfs.ext4.tmp rootfs.ext4
            log_info "Rootfs downloaded successfully"
        else
            log_error "Downloaded rootfs is not valid ext4"
            rm -f rootfs.ext4.tmp
        fi
    else
        log_error "Failed to download rootfs"
    fi
}

# Main function
main() {
    case "${1:-check}" in
        "check")
            check_system
            echo ""
            check_assets
            echo ""
            test_kernel_loading
            ;;
        "download")
            download_fresh_assets
            ;;
        "fix")
            log_info "Running comprehensive fix..."
            check_system
            echo ""
            download_fresh_assets
            echo ""
            check_assets
            echo ""
            log_info "Fix complete. Try running './script.sh' again"
            ;;
        *)
            echo "Usage: $0 [check|download|fix]"
            echo ""
            echo "Commands:"
            echo "  check    - Check system and assets (default)"
            echo "  download - Download fresh assets"
            echo "  fix      - Run comprehensive fix"
            ;;
    esac
}

main "$@"