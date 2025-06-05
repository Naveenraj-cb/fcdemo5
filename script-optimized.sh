#!/bin/bash

# Firecracker Multi-VM Setup Script - Optimized Version
# This script sets up and launches multiple Firecracker microVMs
# Skips downloads if valid files already exist

# Note: Don't use set -e to allow VM startup failures without stopping the entire script

# Configuration
DEFAULT_VM_COUNT=3
DEFAULT_KERNEL_PATH="./vmlinux"
DEFAULT_ROOTFS_PATH="./rootfs.ext4"
DENO_ROOTFS_PATH="./rootfs-deno.ext4"
VM_COUNT=${1:-$DEFAULT_VM_COUNT}
BASE_PORT=8080
FIRECRACKER_VERSION="v1.4.1"
USE_DENO_VMS=false  # Set to true to use Deno-enabled VMs

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
    local source_rootfs="$DEFAULT_ROOTFS_PATH"
    
    # Use Deno rootfs if available and enabled
    if [[ "$USE_DENO_VMS" == "true" ]] && [[ -f "$DENO_ROOTFS_PATH" ]]; then
        source_rootfs="$DENO_ROOTFS_PATH"
        log_info "Using Deno-enabled rootfs for VM $vm_id" >&2
    fi
    
    # Debug: Check if vm_dir exists
    if [[ ! -d "$vm_dir" ]]; then
        log_error "VM directory does not exist: $vm_dir" >&2
        return 1
    fi
    
    # Copy rootfs only if it doesn't exist or is different
    if [[ ! -f "$vm_rootfs" ]] || [[ "$source_rootfs" -nt "$vm_rootfs" ]]; then
        log_info "Creating rootfs for VM $vm_id..." >&2
        cp "$source_rootfs" "$vm_rootfs"
    else
        log_skip "Rootfs for VM $vm_id already exists" >&2
    fi
    
    # Create VM configuration
    log_info "Creating config file: $config_path" >&2
    
    local boot_args="console=ttyS0 reboot=k panic=1 pci=off"
    local mem_size=128
    
    # Use more memory and different boot args for Deno VMs
    if [[ "$USE_DENO_VMS" == "true" ]]; then
        boot_args="console=ttyS0 reboot=k panic=1 pci=off init=/sbin/init"
        mem_size=256
    fi
    
    cat > "$config_path" << EOF
{
  "boot-source": {
    "kernel_image_path": "$(pwd)/$DEFAULT_KERNEL_PATH",
    "boot_args": "$boot_args"
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
    "mem_size_mib": $mem_size
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
    
    # Debug: Verify config file was created
    if [[ ! -f "$config_path" ]]; then
        log_error "Failed to create config file: $config_path" >&2
        return 1
    fi
    
    # Debug: Check config file content
    if [[ ! -s "$config_path" ]]; then
        log_error "Config file is empty: $config_path" >&2
        return 1
    fi
    
    log_info "Config created: $config_path ($(wc -l < "$config_path") lines, ${mem_size}MB RAM)" >&2
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
    if ! sudo ip tuntap add dev "$tap_name" mode tap user "$(whoami)"; then
        log_error "Failed to create TAP interface $tap_name" >&2
        return 1
    fi
    
    # Give each VM a unique IP range: 172.16.{vm_id}.1/24
    local vm_ip="172.16.$vm_id.1/24"
    if ! sudo ip addr add "$vm_ip" dev "$tap_name"; then
        log_error "Failed to assign IP $vm_ip to $tap_name" >&2
        return 1
    fi
    
    if ! sudo ip link set dev "$tap_name" up; then
        log_error "Failed to bring up $tap_name" >&2
        return 1
    fi
    
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
    
    return 0
}

# Start a single VM (optimized with better error handling)
start_vm() {
    local vm_id=$1
    local vm_dir="vms/vm-$vm_id"
    local socket_path="sockets/firecracker-$vm_id.socket"
    local log_path="logs/firecracker-$vm_id.log"
    
    log_info "Starting VM $vm_id..."
    
    # Create VM configuration and get the path
    local config_path
    config_path=$(create_vm_config $vm_id)
    local config_result=$?
    
    # Check if config creation failed
    if [[ $config_result -ne 0 ]] || [[ -z "$config_path" ]]; then
        log_error "Failed to create VM configuration for VM $vm_id" >&2
        return 1
    fi
    
    # Debug: Verify config file was created
    if [[ ! -f "$config_path" ]]; then
        log_error "Config file not created: $config_path" >&2
        return 1
    fi
    
    log_info "Using config: $config_path"
    
    # Setup networking
    if ! setup_vm_network $vm_id; then
        log_error "Failed to setup network for VM $vm_id, but continuing..." >&2
        # Continue anyway - some VMs might work without networking
    fi
    
    # Remove existing socket if it exists
    rm -f "$socket_path"
    
    # Start Firecracker in background
    ./bin/firecracker --api-sock "$socket_path" --config-file "$config_path" > "$log_path" 2>&1 &
    local fc_pid=$!
    
    # Wait for startup
    sleep 3
    
    # Check if firecracker is still running
    if ! kill -0 $fc_pid 2>/dev/null; then
        log_error "Failed to start VM $vm_id" >&2
        log_error "Error log:" >&2
        tail -10 "$log_path" >&2
        return 1
    fi
    
    # Verify socket creation
    if [[ ! -S "$socket_path" ]]; then
        log_error "VM $vm_id started but socket not created" >&2
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
        log_info "Attempting to start VM $i of $VM_COUNT..."
        if start_vm $i; then
            ((success_count++))
            log_info "✅ VM $i started successfully"
        else
            log_error "❌ Failed to start VM $i - continuing with next VM"
        fi
        sleep 1
    done
    
    log_info "VM startup completed: $success_count out of $VM_COUNT VMs started"
    
    if [[ $success_count -eq $VM_COUNT ]]; then
        log_info "🎉 All VMs started successfully!"
        log_info "📁 VM logs: logs/ directory"
        log_info "⚙️  VM configs: vms/ directory"
        log_info "🔌 API sockets: sockets/ directory"
    elif [[ $success_count -gt 0 ]]; then
        log_warn "⚠️  Only $success_count out of $VM_COUNT VMs started successfully"
        log_info "Check individual VM logs in logs/ directory for details"
    else
        log_error "❌ No VMs started successfully"
        log_info "Check logs for error details and run './script-optimized.sh clean' to start fresh"
    fi
}

# Stop all VMs (improved to find actual VMs)
stop_all_vms() {
    log_info "Stopping all VMs..."
    
    local stopped_count=0
    
    if [[ -d "vms" ]]; then
        for vm_dir in vms/vm-*; do
            if [[ -d "$vm_dir" ]]; then
                local vm_id=$(basename "$vm_dir" | sed 's/vm-//')
                local pid_file="$vm_dir/firecracker.pid"
                
                if [[ -f "$pid_file" ]]; then
                    local pid=$(cat "$pid_file")
                    if kill -0 $pid 2>/dev/null; then
                        log_info "Stopping VM $vm_id (PID: $pid)"
                        kill $pid
                        sleep 1
                        # Force kill if still running
                        if kill -0 $pid 2>/dev/null; then
                            kill -9 $pid
                        fi
                        stopped_count=$((stopped_count + 1))
                    fi
                    rm -f "$pid_file"
                fi
                
                # Clean up tap interface
                local tap_name="tap$vm_id"
                if ip link show "$tap_name" &>/dev/null; then
                    sudo ip link del "$tap_name" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    # Clean up iptables rules (basic cleanup)
    sudo iptables -t nat -F POSTROUTING 2>/dev/null || true
    sudo iptables -F FORWARD 2>/dev/null || true
    
    if [[ $stopped_count -gt 0 ]]; then
        log_info "Stopped $stopped_count VM(s) and cleaned up networking"
    else
        log_info "No running VMs found to stop"
    fi
}

# Check VM status
check_vm_status() {
    local running_count=0
    local total_vms=0
    
    if [[ -d "vms" ]]; then
        for vm_dir in vms/vm-*; do
            if [[ -d "$vm_dir" ]]; then
                local vm_id=$(basename "$vm_dir" | sed 's/vm-//')
                local pid_file="$vm_dir/firecracker.pid"
                local socket_path="sockets/firecracker-$vm_id.socket"
                
                total_vms=$((total_vms + 1))
                
                if [[ -f "$pid_file" ]]; then
                    local pid=$(cat "$pid_file")
                    if kill -0 $pid 2>/dev/null; then
                        if [[ -S "$socket_path" ]]; then
                            echo "VM $vm_id: ✅ Running (PID: $pid)"
                            running_count=$((running_count + 1))
                        else
                            echo "VM $vm_id: ⚠️  Running but no socket (PID: $pid)"
                            running_count=$((running_count + 1))
                        fi
                    else
                        echo "VM $vm_id: ❌ Not running (stale PID file)"
                        rm -f "$pid_file"  # Clean up stale PID file
                    fi
                else
                    echo "VM $vm_id: ❌ Not running"
                fi
            fi
        done
    fi
    
    echo "=================================="
    if [[ $total_vms -eq 0 ]]; then
        echo "No VMs found. Use './script-optimized.sh' to start some VMs."
    else
        echo "Running: $running_count/$total_vms VMs"
    fi
}

# Clean assets and directories
clean_assets() {
    log_info "Cleaning assets and directories..."
    stop_all_vms 2>/dev/null || true
    rm -rf vms/ logs/ sockets/ vmlinux rootfs.ext4 bin/
    log_info "Clean completed - all files removed"
}

# Main execution function
main() {
    local command="start"
    local vm_count=$DEFAULT_VM_COUNT
    
    # Parse arguments properly
    if [[ $# -eq 0 ]]; then
        # No arguments: use defaults
        VM_COUNT=$vm_count
        command="start"
    elif [[ $# -eq 1 ]]; then
        # One argument: could be number or command
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            # It's a number - use as VM count
            VM_COUNT=$1
            command="start"
        else
            # It's a command
            VM_COUNT=$vm_count
            command=$1
        fi
    elif [[ $# -eq 2 ]]; then
        # Two arguments: first should be number, second should be command
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            VM_COUNT=$1
            command=$2
        else
            log_error "When using two arguments, first must be a number (VM count)"
            usage
            exit 1
        fi
    else
        # Too many arguments
        usage
        exit 1
    fi
    
    # Debug output
    log_info "Parsed arguments - VM_COUNT: $VM_COUNT, Command: $command" >&2
    
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
            echo "🔍 VM Status Report"
            echo "=================================="
            check_vm_status
            ;;
        "restart")
            stop_all_vms
            sleep 2
            echo "🔄 Restarting VMs..."
            echo "=============================="
            check_root
            check_prerequisites
            setup_directories
            download_assets
            start_all_vms
            ;;
        "clean")
            clean_assets
            ;;
        "deno")
            # Enable Deno VMs for next start
            USE_DENO_VMS=true
            echo "🦕 Enabling Deno VMs..."
            echo "=============================="
            check_root
            check_prerequisites
            setup_directories
            download_assets
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

# Usage information
usage() {
    echo "🔥 Firecracker Multi-VM Demo (Optimized)"
    echo "========================================"
    echo ""
    echo "Usage: $0 [VM_COUNT] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start    - Start VMs (default)"
    echo "  stop     - Stop all VMs"
    echo "  status   - Check VM status"  
    echo "  restart  - Restart all VMs"
    echo "  deno     - Start Deno-enabled VMs"
    echo "  clean    - Clean all assets and start fresh"
    echo "  help     - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                # Start 3 VMs (default)"
    echo "  $0 5              # Start 5 VMs"
    echo "  $0 status         # Check VM status"
    echo "  $0 stop           # Stop all VMs"
    echo "  $0 3 start        # Start 3 VMs explicitly"
    echo "  $0 5 stop         # Stop VMs (VM count ignored for stop)"
    echo "  $0 clean          # Remove all downloaded files"
    echo ""
}

# Run main function
main "$@"