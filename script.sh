#!/bin/bash

# Firecracker Multi-VM Setup Script
# This script sets up and launches multiple Firecracker microVMs

set -e

# Configuration
DEFAULT_VM_COUNT=3
DEFAULT_KERNEL_PATH="./vmlinux"
DEFAULT_ROOTFS_PATH="./rootfs.ext4"
VM_COUNT=${1:-$DEFAULT_VM_COUNT}
BASE_PORT=8080
FIRECRACKER_VERSION="v1.4.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Install Firecracker
install_firecracker() {
    log_info "Installing Firecracker ${FIRECRACKER_VERSION}..."
    
    # Create bin directory if it doesn't exist
    mkdir -p ./bin
    
    # Download Firecracker binary
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        FIRECRACKER_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz"
    else
        log_error "Unsupported architecture: $ARCH. Firecracker supports x86_64 and aarch64."
        exit 1
    fi
    
    log_info "Downloading from: $FIRECRACKER_URL"
    wget -O firecracker.tgz "$FIRECRACKER_URL"
    tar -xzf firecracker.tgz
    
    # Move binaries to bin directory
    mv release-${FIRECRACKER_VERSION}-${ARCH}/firecracker-${FIRECRACKER_VERSION}-${ARCH} ./bin/firecracker
    mv release-${FIRECRACKER_VERSION}-${ARCH}/jailer-${FIRECRACKER_VERSION}-${ARCH} ./bin/jailer
    
    # Make executable
    chmod +x ./bin/firecracker ./bin/jailer
    
    # Clean up
    rm -rf release-${FIRECRACKER_VERSION}-${ARCH} firecracker.tgz
    
    log_info "Firecracker installed successfully"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if firecracker is installed
    if ! command -v ./bin/firecracker &> /dev/null; then
        log_warn "Firecracker not found locally. Installing..."
        install_firecracker
    else
        log_info "Firecracker found: $(./bin/firecracker --version)"
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found. Installing curl..."
        sudo apt-get update && sudo apt-get install -y curl
    fi
    
    # Check if wget is installed
    if ! command -v wget &> /dev/null; then
        log_warn "wget not found. Installing wget..."
        sudo apt-get update && sudo apt-get install -y wget
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found. Installing jq for JSON handling..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
    
    # Check KVM support
    if [[ ! -r /dev/kvm ]]; then
        log_error "KVM is not available or accessible. Firecracker requires KVM."
        log_info "Please ensure:"
        log_info "1. Your CPU supports virtualization"
        log_info "2. Virtualization is enabled in BIOS"
        log_info "3. KVM modules are loaded: sudo modprobe kvm_intel (or kvm_amd)"
        log_info "4. Your user is in the kvm group: sudo usermod -a -G kvm \$USER"
        exit 1
    fi
    
    log_info "Prerequisites check completed"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p vms
    mkdir -p logs
    mkdir -p sockets
    
    # Clean up any existing VM directories
    for i in $(seq 1 $VM_COUNT); do
        rm -rf "vms/vm-$i"
        mkdir -p "vms/vm-$i"
    done
    
    log_info "Directories setup completed"
}

# Download kernel and rootfs if not present
download_assets() {
    log_info "Checking for kernel and rootfs..."
    
    if [[ ! -f "$DEFAULT_KERNEL_PATH" ]]; then
        log_info "Downloading kernel..."
        wget -O "$DEFAULT_KERNEL_PATH" \
            https://github.com/firecracker-microvm/firecracker-demo/releases/download/v0.1/vmlinux
    fi
    
    if [[ ! -f "$DEFAULT_ROOTFS_PATH" ]]; then
        log_info "Downloading rootfs..."
        wget -O "$DEFAULT_ROOTFS_PATH" \
            https://github.com/firecracker-microvm/firecracker-demo/releases/download/v0.1/rootfs.ext4
    fi
    
    log_info "Assets check completed"
}

# Create VM configuration
create_vm_config() {
    local vm_id=$1
    local vm_dir="vms/vm-$vm_id"
    local socket_path="sockets/firecracker-$vm_id.socket"
    local log_path="logs/firecracker-$vm_id.log"
    local config_path="$vm_dir/config.json"
    
    # Create individual rootfs for each VM
    cp "$DEFAULT_ROOTFS_PATH" "$vm_dir/rootfs.ext4"
    
    # Create VM configuration
    cat > "$config_path" << EOF
{
  "boot-source": {
    "kernel_image_path": "$(pwd)/$DEFAULT_KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$(pwd)/$vm_dir/rootfs.ext4",
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
      "guest_mac": "AA:FC:00:00:00:$(printf '%02d' $vm_id)",
      "host_dev_name": "tap$vm_id"
    }
  ]
}
EOF
    
    echo "$config_path"
}

# Setup networking for VM
setup_vm_network() {
    local vm_id=$1
    local tap_name="tap$vm_id"
    
    # Create TAP interface
    sudo ip tuntap add dev "$tap_name" mode tap user "$(whoami)"
    sudo ip addr add "172.16.0.1/24" dev "$tap_name"
    sudo ip link set dev "$tap_name" up
    
    # Enable IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # Setup iptables rules for NAT
    sudo iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    sudo iptables -A FORWARD -i "$tap_name" -j ACCEPT
    sudo iptables -A FORWARD -o "$tap_name" -j ACCEPT
}

# Start a single VM
start_vm() {
    local vm_id=$1
    local vm_dir="vms/vm-$vm_id"
    local socket_path="sockets/firecracker-$vm_id.socket"
    local log_path="logs/firecracker-$vm_id.log"
    local config_path=$(create_vm_config $vm_id)
    
    log_info "Starting VM $vm_id..."
    
    # Setup networking
    setup_vm_network $vm_id
    
    # Remove existing socket if it exists
    rm -f "$socket_path"
    
    # Start Firecracker in background using local binary
    ./bin/firecracker --api-sock "$socket_path" --config-file "$config_path" > "$log_path" 2>&1 &
    local fc_pid=$!
    
    # Wait a moment for the socket to be created
    sleep 2
    
    # Check if firecracker is still running
    if ! kill -0 $fc_pid 2>/dev/null; then
        log_error "Failed to start VM $vm_id"
        cat "$log_path"
        return 1
    fi
    
    # Store PID for cleanup
    echo $fc_pid > "$vm_dir/firecracker.pid"
    
    log_info "VM $vm_id started successfully (PID: $fc_pid)"
    return 0
}

# Start all VMs
start_all_vms() {
    log_info "Starting $VM_COUNT Firecracker VMs..."
    
    local success_count=0
    
    for i in $(seq 1 $VM_COUNT); do
        if start_vm $i; then
            ((success_count++))
        else
            log_error "Failed to start VM $i"
        fi
        sleep 1
    done
    
    log_info "Successfully started $success_count out of $VM_COUNT VMs"
    
    if [[ $success_count -eq $VM_COUNT ]]; then
        log_info "All VMs started successfully!"
        log_info "VM logs are available in the 'logs/' directory"
        log_info "VM configurations are in the 'vms/' directory"
    fi
}

# Stop all VMs
stop_all_vms() {
    log_info "Stopping all VMs..."
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_dir="vms/vm-$i"
        local pid_file="$vm_dir/firecracker.pid"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if kill -0 $pid 2>/dev/null; then
                log_info "Stopping VM $i (PID: $pid)"
                kill $pid
                sleep 1
                # Force kill if still running
                if kill -0 $pid 2>/dev/null; then
                    kill -9 $pid
                fi
            fi
            rm -f "$pid_file"
        fi
        
        # Clean up tap interface
        local tap_name="tap$i"
        if ip link show "$tap_name" &>/dev/null; then
            sudo ip link del "$tap_name"
        fi
    done
    
    # Clean up iptables rules (basic cleanup)
    sudo iptables -t nat -F POSTROUTING 2>/dev/null || true
    sudo iptables -F FORWARD 2>/dev/null || true
    
    log_info "All VMs stopped and cleaned up"
}

# Check VM status
check_vm_status() {
    log_info "Checking VM status..."
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_dir="vms/vm-$i"
        local pid_file="$vm_dir/firecracker.pid"
        local socket_path="sockets/firecracker-$i.socket"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if kill -0 $pid 2>/dev/null; then
                if [[ -S "$socket_path" ]]; then
                    log_info "VM $i: Running (PID: $pid, Socket: OK)"
                else
                    log_warn "VM $i: Running (PID: $pid, Socket: Missing)"
                fi
            else
                log_warn "VM $i: Not running (stale PID file)"
            fi
        else
            log_warn "VM $i: Not running (no PID file)"
        fi
    done
}

# Usage information
usage() {
    echo "Usage: $0 [VM_COUNT] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start    - Start VMs (default)"
    echo "  stop     - Stop all VMs"
    echo "  status   - Check VM status"
    echo "  restart  - Restart all VMs"
    echo ""
    echo "Examples:"
    echo "  $0           # Start 3 VMs (default)"
    echo "  $0 5         # Start 5 VMs"
    echo "  $0 3 stop    # Stop all VMs"
    echo "  $0 status    # Check status"
}

# Main execution
main() {
    local command="start"
    
    # Parse arguments
    if [[ $# -eq 1 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        VM_COUNT=$1
    elif [[ $# -eq 1 ]] && [[ "$1" != "start" ]]; then
        command=$1
    elif [[ $# -eq 2 ]]; then
        VM_COUNT=$1
        command=$2
    elif [[ $# -gt 2 ]]; then
        usage
        exit 1
    fi
    
    # Handle commands
    case $command in
        "start")
            check_root
            check_prerequisites
            setup_directories
            download_assets
            start_all_vms
            ;;
        "stop")
            stop_all_vms
            ;;
        "status")
            check_vm_status
            ;;
        "restart")
            stop_all_vms
            sleep 2
            check_root
            check_prerequisites
            setup_directories
            start_all_vms
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Trap to cleanup on exit
trap 'stop_all_vms' EXIT

# Run main function
main "$@"