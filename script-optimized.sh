#!/bin/bash

# Firecracker Multi-VM Setup Script - Optimized Version
# This script sets up and launches multiple Firecracker microVMs
# Skips downloads if valid files already exist

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

log_skip() {
    echo -e "${BLUE}[SKIP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Install Firecracker (optimized with skip logic)
install_firecracker() {
    log_info "Checking Firecracker installation..."
    
    # Create bin directory if it doesn't exist
    mkdir -p ./bin
    
    # Check if binaries already exist and are the correct version
    if [[ -x "./bin/firecracker" && -x "./bin/jailer" ]]; then
        local existing_version=$(./bin/firecracker --version 2>/dev/null | head -1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
        if [[ "$existing_version" == "$FIRECRACKER_VERSION" ]]; then
            log_skip "Firecracker ${FIRECRACKER_VERSION} already installed"
            return 0
        else
            log_warn "Found version $existing_version, updating to ${FIRECRACKER_VERSION}"
        fi
    fi
    
    log_info "Installing Firecracker ${FIRECRACKER_VERSION}..."
    
    # Download Firecracker binary
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        FIRECRACKER_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz"
    else
        log_error "Unsupported architecture: $ARCH. Firecracker supports x86_64 and aarch64."
        exit 1
    fi
    
    log_info "Downloading from: $FIRECRACKER_URL"
    wget -q --show-progress -O firecracker.tgz "$FIRECRACKER_URL"
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

# Check prerequisites (optimized)
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Firecracker installation
    install_firecracker
    
    # Check required tools (install only if missing)
    local tools=("curl" "wget" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warn "Installing missing tools: ${missing_tools[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${missing_tools[@]}"
    else
        log_skip "All required tools already installed"
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

# Setup directories (optimized)
setup_directories() {
    log_info "Setting up directories..."
    
    # Create base directories if they don't exist
    local dirs=("vms" "logs" "sockets")
    for dir in "${dirs[@]}"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
    
    # Clean up any existing VM directories and recreate
    for i in $(seq 1 $VM_COUNT); do
        rm -rf "vms/vm-$i"
        mkdir -p "vms/vm-$i"
    done
    
    log_info "Directories setup completed"
}

# Optimized asset download with skip logic
download_assets() {
    log_info "Checking assets..."
    
    local kernel_valid=false
    local rootfs_valid=false
    
    # Check kernel
    if [[ -f "$DEFAULT_KERNEL_PATH" ]]; then
        if file "$DEFAULT_KERNEL_PATH" | grep -q "ELF"; then
            local kernel_size=$(stat -c%s "$DEFAULT_KERNEL_PATH")
            if [[ $kernel_size -gt 1000000 ]]; then  # At least 1MB
                log_skip "Valid kernel already exists (${kernel_size} bytes)"
                kernel_valid=true
            else
                log_warn "Kernel file too small, re-downloading..."
            fi
        else
            log_warn "Kernel file corrupted, re-downloading..."
        fi
    fi
    
    # Download kernel if needed
    if [[ "$kernel_valid" != "true" ]]; then
        log_info "Downloading kernel..."
        
        # Try multiple kernel sources
        local kernel_urls=(
            "https://github.com/firecracker-microvm/firecracker-demo/releases/download/v0.1/vmlinux"
            "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin"
        )
        
        for url in "${kernel_urls[@]}"; do
            log_info "Trying: $url"
            if wget -q --show-progress -O "$DEFAULT_KERNEL_PATH.tmp" "$url"; then
                if [[ -s "$DEFAULT_KERNEL_PATH.tmp" ]] && file "$DEFAULT_KERNEL_PATH.tmp" | grep -q "ELF"; then
                    mv "$DEFAULT_KERNEL_PATH.tmp" "$DEFAULT_KERNEL_PATH"
                    log_info "Kernel downloaded successfully from: $url"
                    kernel_valid=true
                    break
                else
                    log_warn "Invalid kernel from: $url"
                    rm -f "$DEFAULT_KERNEL_PATH.tmp"
                fi
            else
                log_warn "Failed to download from: $url"
            fi
        done
        
        if [[ "$kernel_valid" != "true" ]]; then
            log_error "Failed to download a valid kernel"
            exit 1
        fi
    fi
    
    # Check rootfs
    if [[ -f "$DEFAULT_ROOTFS_PATH" ]]; then
        if file "$DEFAULT_ROOTFS_PATH" | grep -q "ext.*filesystem"; then
            local rootfs_size=$(stat -c%s "$DEFAULT_ROOTFS_PATH")
            if [[ $rootfs_size -gt 10000000 ]]; then  # At least 10MB
                log_skip "Valid rootfs already exists (${rootfs_size} bytes)"
                rootfs_valid=true
            else
                log_warn "Rootfs file too small, re-downloading..."
            fi
        else
            log_warn "Rootfs file corrupted, re-downloading..."
        fi
    fi
    
    # Download rootfs if needed
    if [[ "$rootfs_valid" != "true" ]]; then
        log_info "Downloading rootfs..."
        
        if wget -q --show-progress -O "$DEFAULT_ROOTFS_PATH.tmp" \
            "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/rootfs/bionic.rootfs.ext4"; then
            
            if [[ -s "$DEFAULT_ROOTFS_PATH.tmp" ]] && file "$DEFAULT_ROOTFS_PATH.tmp" | grep -q "ext.*filesystem"; then
                mv "$DEFAULT_ROOTFS_PATH.tmp" "$DEFAULT_ROOTFS_PATH"
                log_info "Rootfs downloaded successfully"
                rootfs_valid=true
            else
                log_error "Downloaded rootfs is invalid"
                rm -f "$DEFAULT_ROOTFS_PATH.tmp"
                exit 1
            fi
        else
            log_error "Failed to download rootfs"
            exit 1
        fi
    fi
    
    log_info "Assets ready"
}

# Create VM configuration (optimized to avoid copying if exists)
create_vm_config() {
    local vm_id=$1
    local vm_dir="vms/vm-$vm_id"
    local config_path="$vm_dir/config.json"
    local vm_rootfs="$vm_dir/rootfs.ext4"
    
    # Copy rootfs only if it doesn't exist or is different
    if [[ ! -f "$vm_rootfs" ]] || [[ "$DEFAULT_ROOTFS_PATH" -nt "$vm_rootfs" ]]; then
        log_info "Creating rootfs for VM $vm_id..."
        cp "$DEFAULT_ROOTFS_PATH" "$vm_rootfs"
    else
        log_skip "Rootfs for VM $vm_id already exists"
    fi
    
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
      "guest_mac": "AA:FC:00:00:00:$(printf '%02d' $vm_id)",
      "host_dev_name": "tap$vm_id"
    }
  ]
}
EOF
    
    echo "$config_path"
}

# Setup networking for VM (with skip logic)
setup_vm_network() {
    local vm_id=$1
    local tap_name="tap$vm_id"
    
    # Check if TAP interface already exists
    if ip link show "$tap_name" &>/dev/null; then
        log_skip "TAP interface $tap_name already exists"
        return 0
    fi
    
    log_info "Setting up network for VM $vm_id..."
    
    # Create TAP interface
    sudo ip tuntap add dev "$tap_name" mode tap user "$(whoami)"
    sudo ip addr add "172.16.0.1/24" dev "$tap_name"
    sudo ip link set dev "$tap_name" up
    
    # Enable IP forwarding (only if not already enabled)
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) != "1" ]]; then
        echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    fi
    
    # Setup iptables rules for NAT (avoid duplicates)
    local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if ! sudo iptables -t nat -C POSTROUTING -o "$default_iface" -j MASQUERADE 2>/dev/null; then
        sudo iptables -t nat -A POSTROUTING -o "$default_iface" -j MASQUERADE
    fi
    if ! sudo iptables -C FORWARD -i "$tap_name" -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i "$tap_name" -j ACCEPT
        sudo iptables -A FORWARD -o "$tap_name" -j ACCEPT
    fi
}

# Start a single VM (optimized with better error handling)
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
    
    # Start Firecracker in background
    ./bin/firecracker --api-sock "$socket_path" --config-file "$config_path" > "$log_path" 2>&1 &
    local fc_pid=$!
    
    # Wait for startup
    sleep 3
    
    # Check if firecracker is still running
    if ! kill -0 $fc_pid 2>/dev/null; then
        log_error "Failed to start VM $vm_id"
        log_error "Error log:"
        tail -10 "$log_path"
        return 1
    fi
    
    # Verify socket creation
    if [[ ! -S "$socket_path" ]]; then
        log_error "VM $vm_id started but socket not created"
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
        log_info "🎉 All VMs started successfully!"
        log_info "📁 VM logs: logs/ directory"
        log_info "⚙️  VM configs: vms/ directory"
        log_info "🔌 API sockets: sockets/ directory"
    else
        log_warn "Some VMs failed to start. Check logs for details."
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
    
    log_info "All VMs stopped and cleaned up"
}

# Check VM status
check_vm_status() {
    log_info "VM Status Report:"
    echo "=================================="
    
    local running_count=0
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_dir="vms/vm-$i"
        local pid_file="$vm_dir/firecracker.pid"
        local socket_path="sockets/firecracker-$i.socket"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if kill -0 $pid 2>/dev/null; then
                if [[ -S "$socket_path" ]]; then
                    echo "VM $i: ✅ Running (PID: $pid)"
                    ((running_count++))
                else
                    echo "VM $i: ⚠️  Running but no socket (PID: $pid)"
                fi
            else
                echo "VM $i: ❌ Not running (stale PID file)"
            fi
        else
            echo "VM $i: ❌ Not running"
        fi
    done
    
    echo "=================================="
    echo "Running: $running_count/$VM_COUNT VMs"
}

# Clean assets and directories
clean_assets() {
    log_info "Cleaning assets and directories..."
    stop_all_vms 2>/dev/null || true
    rm -rf vms/ logs/ sockets/ vmlinux rootfs.ext4 bin/
    log_info "Clean completed - all files removed"
}

# Usage information
usage() {
    echo "🔥 Firecracker Multi-VM Manager"
    echo "Usage: $0 [VM_COUNT] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start    - Start VMs (default)"
    echo "  stop     - Stop all VMs"
    echo "  status   - Check VM status"
    echo "  restart  - Restart all VMs"
    echo "  clean    - Clean all assets and start fresh"
    echo ""
    echo "Examples:"
    echo "  $0           # Start 3 VMs (default)"
    echo "  $0 5         # Start 5 VMs"
    echo "  $0 3 stop    # Stop all VMs"
    echo "  $0 status    # Check status"
    echo "  $0 clean     # Remove all downloaded files"
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
            echo "🔥 Firecracker Multi-VM Setup"
            echo "=============================="
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
            echo "🔄 Restarting VMs..."
            check_root
            check_prerequisites
            setup_directories
            download_assets
            start_all_vms
            ;;
        "clean")
            clean_assets
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