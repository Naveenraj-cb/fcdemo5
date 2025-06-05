#!/bin/bash

# Test script for Firecracker Multi-VM setup

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test VM startup and basic functionality
test_vm_startup() {
    log_test "Testing VM startup with 2 VMs..."
    
    # Start 2 VMs
    ./script.sh 2 start
    
    # Wait a bit for VMs to fully start
    sleep 5
    
    # Check status
    ./script.sh status
    
    # Verify files exist
    if [[ -f "vms/vm-1/firecracker.pid" && -f "vms/vm-2/firecracker.pid" ]]; then
        log_info "VM PID files created successfully"
    else
        log_error "VM PID files not found"
        return 1
    fi
    
    # Verify sockets exist
    if [[ -S "sockets/firecracker-1.socket" && -S "sockets/firecracker-2.socket" ]]; then
        log_info "VM sockets created successfully"
    else
        log_error "VM sockets not found"
        return 1
    fi
    
    # Verify processes are running
    local pid1=$(cat vms/vm-1/firecracker.pid)
    local pid2=$(cat vms/vm-2/firecracker.pid)
    
    if kill -0 $pid1 2>/dev/null && kill -0 $pid2 2>/dev/null; then
        log_info "VM processes are running"
    else
        log_error "VM processes not running"
        return 1
    fi
    
    # Verify network interfaces
    if ip link show tap1 &>/dev/null && ip link show tap2 &>/dev/null; then
        log_info "TAP interfaces created successfully"
    else
        log_error "TAP interfaces not found"
        return 1
    fi
    
    log_info "VM startup test passed!"
    return 0
}

# Test VM stop functionality
test_vm_stop() {
    log_test "Testing VM stop functionality..."
    
    # Stop VMs
    ./script.sh stop
    
    # Wait a bit
    sleep 2
    
    # Verify processes are stopped
    if [[ -f "vms/vm-1/firecracker.pid" ]]; then
        local pid1=$(cat vms/vm-1/firecracker.pid 2>/dev/null || echo "")
        if [[ -n "$pid1" ]] && kill -0 $pid1 2>/dev/null; then
            log_error "VM 1 process still running"
            return 1
        fi
    fi
    
    # Verify TAP interfaces are cleaned up
    if ip link show tap1 &>/dev/null || ip link show tap2 &>/dev/null; then
        log_error "TAP interfaces not cleaned up"
        return 1
    fi
    
    log_info "VM stop test passed!"
    return 0
}

# Test asset download
test_asset_download() {
    log_test "Testing asset download..."
    
    # Remove assets if they exist
    rm -f vmlinux rootfs.ext4
    
    # Run download (this happens during start)
    ./script.sh 1 start
    
    # Check if assets were downloaded
    if [[ -f "vmlinux" && -f "rootfs.ext4" ]]; then
        log_info "Assets downloaded successfully"
        
        # Check file sizes (should be reasonable)
        local kernel_size=$(stat -c%s vmlinux)
        local rootfs_size=$(stat -c%s rootfs.ext4)
        
        if [[ $kernel_size -gt 1000000 && $rootfs_size -gt 1000000 ]]; then
            log_info "Asset sizes look reasonable (kernel: ${kernel_size} bytes, rootfs: ${rootfs_size} bytes)"
        else
            log_error "Asset sizes seem too small"
            return 1
        fi
    else
        log_error "Assets not downloaded"
        return 1
    fi
    
    # Stop the test VM
    ./script.sh stop
    
    log_info "Asset download test passed!"
    return 0
}

# Run all tests
run_tests() {
    echo "=========================================="
    echo "   Firecracker Multi-VM Test Suite"
    echo "=========================================="
    echo ""
    
    local failed_tests=0
    
    # Test 1: Asset download
    if ! test_asset_download; then
        ((failed_tests++))
        log_error "Asset download test failed"
    fi
    echo ""
    
    # Test 2: VM startup
    if ! test_vm_startup; then
        ((failed_tests++))
        log_error "VM startup test failed"
    fi
    echo ""
    
    # Test 3: VM stop
    if ! test_vm_stop; then
        ((failed_tests++))
        log_error "VM stop test failed"
    fi
    echo ""
    
    # Final cleanup
    ./script.sh stop 2>/dev/null || true
    
    # Results
    echo "=========================================="
    if [[ $failed_tests -eq 0 ]]; then
        log_info "All tests passed! ✅"
        echo "Your Firecracker setup is working correctly."
    else
        log_error "$failed_tests test(s) failed! ❌"
        echo "Please check the errors above and ensure:"
        echo "1. You ran setup.sh first"
        echo "2. You have proper permissions (kvm group)"
        echo "3. KVM is supported and enabled"
        exit 1
    fi
    echo "=========================================="
}

# Check prerequisites
check_prerequisites() {
    if [[ ! -f "script.sh" ]]; then
        log_error "script.sh not found. Please run this from the project directory."
        exit 1
    fi
    
    if [[ ! -x "script.sh" ]]; then
        log_error "script.sh is not executable. Run: chmod +x script.sh"
        exit 1
    fi
    
    if ! command -v firecracker &> /dev/null; then
        log_error "Firecracker not found. Please run setup.sh first."
        exit 1
    fi
}

# Main function
main() {
    check_prerequisites
    run_tests
}

# Run main function
main "$@"