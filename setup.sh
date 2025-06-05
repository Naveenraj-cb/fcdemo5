#!/bin/bash

# Firecracker Setup Script
# This script sets up the environment for running Firecracker VMs on Ubuntu

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running on Ubuntu
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu. Your OS may not be supported."
        exit 1
    fi
    log_info "Ubuntu detected: $(lsb_release -d | cut -f2)"
}

# Check KVM support
check_kvm_support() {
    log_step "Checking KVM support..."
    
    # Check CPU virtualization support
    if ! egrep -q '(vmx|svm)' /proc/cpuinfo; then
        log_error "CPU virtualization not supported or not enabled in BIOS"
        log_error "Please enable VT-x (Intel) or AMD-V (AMD) in your BIOS settings"
        exit 1
    fi
    log_info "CPU virtualization support: OK"
    
    # Check if KVM modules are available
    if ! lsmod | grep -q kvm; then
        log_warn "KVM modules not loaded. Attempting to load..."
        sudo modprobe kvm
        if grep -q "Intel" /proc/cpuinfo; then
            sudo modprobe kvm_intel
        else
            sudo modprobe kvm_amd
        fi
    fi
    log_info "KVM modules: OK"
    
    # Check KVM device
    if [[ ! -c /dev/kvm ]]; then
        log_error "/dev/kvm not found. KVM may not be properly installed."
        exit 1
    fi
    log_info "KVM device: OK"
}

# Setup user permissions
setup_permissions() {
    log_step "Setting up user permissions..."
    
    # Add user to kvm group
    if ! groups $USER | grep -q kvm; then
        log_info "Adding user to kvm group..."
        sudo usermod -a -G kvm $USER
        log_warn "You need to log out and log back in for group changes to take effect"
        log_warn "Or run: newgrp kvm"
    else
        log_info "User already in kvm group: OK"
    fi
}

# Install dependencies
install_dependencies() {
    log_step "Installing dependencies..."
    
    # Update package list
    log_info "Updating package list..."
    sudo apt update
    
    # Install Firecracker
    if ! command -v firecracker &> /dev/null; then
        log_info "Installing Firecracker..."
        sudo apt install -y firecracker
    else
        log_info "Firecracker already installed: $(firecracker --version | head -1)"
    fi
    
    # Install other tools
    local tools=("curl" "wget" "jq" "iproute2" "iptables")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_info "Installing $tool..."
            sudo apt install -y $tool
        else
            log_info "$tool already installed: OK"
        fi
    done
}

# Test Firecracker
test_firecracker() {
    log_step "Testing Firecracker installation..."
    
    # Test Firecracker version
    local version=$(firecracker --version | head -1)
    log_info "Firecracker version: $version"
    
    # Test if firecracker can access KVM
    if timeout 5 firecracker --api-sock /tmp/test.socket 2>/dev/null &
    then
        local pid=$!
        sleep 1
        kill $pid 2>/dev/null || true
        rm -f /tmp/test.socket
        log_info "Firecracker KVM access: OK"
    else
        log_error "Firecracker cannot access KVM. Check permissions."
        exit 1
    fi
}

# Setup network prerequisites
setup_network() {
    log_step "Setting up network prerequisites..."
    
    # Enable IP forwarding
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) != "1" ]]; then
        log_info "Enabling IP forwarding..."
        echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
    else
        log_info "IP forwarding already enabled: OK"
    fi
    
    # Check iptables
    if ! command -v iptables &> /dev/null; then
        log_error "iptables not found"
        exit 1
    fi
    log_info "iptables available: OK"
}

# Create project structure
create_project_structure() {
    log_step "Creating project structure..."
    
    # Make script executable
    chmod +x script.sh
    log_info "Made script.sh executable"
    
    # Create basic directories (they'll be recreated by the main script)
    mkdir -p vms logs sockets
    log_info "Created directory structure"
}

# Main setup function
main() {
    echo "=========================================="
    echo "   Firecracker Setup Script"
    echo "=========================================="
    echo ""
    
    check_ubuntu
    check_kvm_support
    setup_permissions
    install_dependencies
    setup_network
    test_firecracker
    create_project_structure
    
    echo ""
    echo "=========================================="
    log_info "Setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. If you were added to the kvm group, log out and log back in"
    echo "2. Run './script.sh' to start 3 VMs"
    echo "3. Run './script.sh 5' to start 5 VMs"
    echo "4. Run './script.sh status' to check VM status"
    echo "5. Run './script.sh stop' to stop all VMs"
    echo ""
    echo "For more information, see README.md"
}

# Run main function
main "$@"