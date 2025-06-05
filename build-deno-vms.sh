#!/bin/bash

# Firecracker + Deno VM Builder Script
# This script creates custom VM images with Deno runtime and our application

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root"
    exit 1
fi

# Configuration
WORK_DIR="$(pwd)/vm-builder"
MOUNT_DIR="$WORK_DIR/mnt"
DENO_VERSION="v1.40.5"
BASE_ROOTFS="./rootfs.ext4"
CUSTOM_ROOTFS="./rootfs-deno.ext4"

# Create working directory
setup_workspace() {
    log_step "Setting up workspace..."
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR" "$MOUNT_DIR"
    
    # Check if base rootfs exists
    if [[ ! -f "$BASE_ROOTFS" ]]; then
        log_error "Base rootfs not found: $BASE_ROOTFS"
        log_info "Run './script-optimized.sh' first to download the base rootfs"
        exit 1
    fi
    
    log_info "Workspace ready: $WORK_DIR"
}

# Create custom rootfs with more space
create_custom_rootfs() {
    log_step "Creating custom rootfs with Deno..."
    
    # Copy base rootfs and extend it
    cp "$BASE_ROOTFS" "$CUSTOM_ROOTFS"
    
    # Resize the filesystem to add space for Deno (~100MB)
    log_info "Expanding rootfs for Deno installation..."
    dd if=/dev/zero bs=1M count=200 >> "$CUSTOM_ROOTFS"
    e2fsck -f "$CUSTOM_ROOTFS" || true
    resize2fs "$CUSTOM_ROOTFS"
    
    log_info "Custom rootfs created: $CUSTOM_ROOTFS"
}

# Mount rootfs and install Deno
install_deno_in_rootfs() {
    log_step "Installing Deno in rootfs..."
    
    # Mount the rootfs
    sudo mount -o loop "$CUSTOM_ROOTFS" "$MOUNT_DIR"
    
    # Download Deno binary
    log_info "Downloading Deno $DENO_VERSION..."
    local deno_url="https://github.com/denoland/deno/releases/download/$DENO_VERSION/deno-x86_64-unknown-linux-gnu.zip"
    wget -q -O "$WORK_DIR/deno.zip" "$deno_url"
    
    # Extract and install Deno
    unzip -q "$WORK_DIR/deno.zip" -d "$WORK_DIR"
    sudo mkdir -p "$MOUNT_DIR/usr/local/bin"
    sudo cp "$WORK_DIR/deno" "$MOUNT_DIR/usr/local/bin/"
    sudo chmod +x "$MOUNT_DIR/usr/local/bin/deno"
    
    # Create app directory
    sudo mkdir -p "$MOUNT_DIR/app"
    
    # Copy our Deno application
    sudo cp "deno-app/server.ts" "$MOUNT_DIR/app/"
    
    # Create startup script
    cat > "$WORK_DIR/start-deno-app.sh" << 'EOF'
#!/bin/bash

# Deno App Startup Script for Firecracker VM

export VM_ID=${VM_ID:-"1"}
export PORT=${PORT:-"8000"}
export VM_COUNT=${VM_COUNT:-"3"}

echo "🔥 Starting Deno app in VM $VM_ID"
echo "📡 Port: $PORT"
echo "🏗️  VM Count: $VM_COUNT"

# Wait for network to be ready
sleep 2

# Configure IP address for this VM
if [[ -n "$VM_ID" ]]; then
    # Set IP address based on VM ID
    ip addr add 172.16.${VM_ID}.2/24 dev eth0
    ip link set eth0 up
    
    # Add default route
    ip route add default via 172.16.${VM_ID}.1
    
    echo "🌐 Network configured: 172.16.${VM_ID}.2/24"
fi

# Start the Deno application
echo "🚀 Launching Deno server..."
cd /app
exec /usr/local/bin/deno run --allow-net --allow-env --allow-read server.ts
EOF
    
    sudo cp "$WORK_DIR/start-deno-app.sh" "$MOUNT_DIR/app/"
    sudo chmod +x "$MOUNT_DIR/app/start-deno-app.sh"
    
    # Create systemd service for auto-start
    cat > "$WORK_DIR/deno-app.service" << EOF
[Unit]
Description=Deno HTTP Server
After=network.target

[Service]
Type=exec
User=root
WorkingDirectory=/app
Environment=VM_ID=1
Environment=PORT=8000
Environment=VM_COUNT=3
ExecStart=/app/start-deno-app.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    sudo cp "$WORK_DIR/deno-app.service" "$MOUNT_DIR/etc/systemd/system/"
    
    # Enable the service (will start on boot)
    sudo chroot "$MOUNT_DIR" systemctl enable deno-app.service
    
    # Create network configuration script
    cat > "$WORK_DIR/setup-network.sh" << 'EOF'
#!/bin/bash
# This script will be called by our Firecracker setup to configure networking
VM_ID=$1
if [[ -n "$VM_ID" ]]; then
    # Configure the VM's internal network
    ip addr add 172.16.${VM_ID}.2/24 dev eth0
    ip link set eth0 up
    ip route add default via 172.16.${VM_ID}.1
    
    # Update environment for the service
    sed -i "s/VM_ID=1/VM_ID=${VM_ID}/" /etc/systemd/system/deno-app.service
    systemctl daemon-reload
    systemctl restart deno-app.service
fi
EOF
    
    sudo cp "$WORK_DIR/setup-network.sh" "$MOUNT_DIR/usr/local/bin/"
    sudo chmod +x "$MOUNT_DIR/usr/local/bin/setup-network.sh"
    
    # Install curl for inter-VM communication testing
    log_info "Installing curl in VM..."
    sudo chroot "$MOUNT_DIR" apt-get update -qq
    sudo chroot "$MOUNT_DIR" apt-get install -y curl
    
    # Unmount
    sudo umount "$MOUNT_DIR"
    
    log_info "Deno installed successfully in rootfs"
}

# Update the VM configuration template
update_vm_config_template() {
    log_step "Creating VM configuration template..."
    
    cat > vm-config-template.json << 'EOF'
{
  "boot-source": {
    "kernel_image_path": "KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/sbin/init"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "ROOTFS_PATH",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 256
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "GUEST_MAC",
      "host_dev_name": "HOST_DEV"
    }
  ]
}
EOF
    
    log_info "VM configuration template created"
}

# Create a test script for the Deno VMs
create_test_script() {
    log_step "Creating test script..."
    
    cat > test-deno-vms.sh << 'EOF'
#!/bin/bash

# Test script for Deno-enabled Firecracker VMs

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test VM health
test_vm_health() {
    local vm_id=$1
    local ip="172.16.${vm_id}.2"
    
    log_info "Testing VM $vm_id health..."
    
    if curl -s --connect-timeout 5 "http://${ip}:8000/health" > /dev/null; then
        log_info "✅ VM $vm_id is healthy"
        return 0
    else
        log_error "❌ VM $vm_id health check failed"
        return 1
    fi
}

# Test inter-VM communication
test_inter_vm_communication() {
    local source_vm=$1
    local target_vm=$2
    local source_ip="172.16.${source_vm}.2"
    
    log_info "Testing communication from VM $source_vm to VM $target_vm..."
    
    local result=$(curl -s --connect-timeout 5 "http://${source_ip}:8000/ping/vm-${target_vm}" | jq -r '.success // false')
    
    if [[ "$result" == "true" ]]; then
        log_info "✅ VM $source_vm can communicate with VM $target_vm"
        return 0
    else
        log_error "❌ Communication failed from VM $source_vm to VM $target_vm"
        return 1
    fi
}

# Test cluster status
test_cluster_status() {
    log_info "Testing cluster status..."
    
    local vm_ip="172.16.1.2"
    local cluster_data=$(curl -s --connect-timeout 5 "http://${vm_ip}:8000/cluster-status")
    
    if [[ $? -eq 0 ]]; then
        echo "$cluster_data" | jq '.'
        local online_vms=$(echo "$cluster_data" | jq -r '.cluster_health.online_vms // 0')
        log_info "✅ Cluster status: $online_vms VMs online"
    else
        log_error "❌ Failed to get cluster status"
    fi
}

# Test data storage and retrieval
test_data_operations() {
    local vm_ip="172.16.1.2"
    
    log_info "Testing data storage operations..."
    
    # Store data
    curl -s -X POST "http://${vm_ip}:8000/storage/test" \
         -H "Content-Type: application/json" \
         -d '{"message": "Hello from test!", "timestamp": "'$(date -Iseconds)'"}' > /dev/null
    
    # Retrieve data
    local stored_data=$(curl -s "http://${vm_ip}:8000/storage/test")
    
    if echo "$stored_data" | jq -e '.value.message' > /dev/null; then
        log_info "✅ Data storage and retrieval working"
        echo "$stored_data" | jq '.'
    else
        log_error "❌ Data storage test failed"
    fi
}

# Test broadcast functionality
test_broadcast() {
    local vm_ip="172.16.1.2"
    
    log_info "Testing broadcast functionality..."
    
    local broadcast_result=$(curl -s -X POST "http://${vm_ip}:8000/broadcast" \
                           -H "Content-Type: application/json" \
                           -d '{"type": "test", "message": "Broadcast test from script"}')
    
    if echo "$broadcast_result" | jq -e '.successful' > /dev/null; then
        local successful=$(echo "$broadcast_result" | jq -r '.successful')
        log_info "✅ Broadcast sent to $successful VMs"
        echo "$broadcast_result" | jq '.'
    else
        log_error "❌ Broadcast test failed"
    fi
}

# Main test execution
main() {
    echo "🧪 Testing Deno-enabled Firecracker VMs"
    echo "========================================"
    
    # Wait for VMs to be ready
    log_info "Waiting for VMs to start up..."
    sleep 10
    
    # Test each VM health
    local healthy_vms=0
    for i in {1..3}; do
        if test_vm_health $i; then
            ((healthy_vms++))
        fi
    done
    
    if [[ $healthy_vms -eq 0 ]]; then
        log_error "No VMs are healthy. Exiting."
        exit 1
    fi
    
    log_info "$healthy_vms out of 3 VMs are healthy"
    
    # Test inter-VM communication
    echo ""
    log_info "Testing inter-VM communication..."
    test_inter_vm_communication 1 2
    test_inter_vm_communication 2 3
    test_inter_vm_communication 3 1
    
    # Test cluster status
    echo ""
    test_cluster_status
    
    # Test data operations
    echo ""
    test_data_operations
    
    # Test broadcast
    echo ""
    test_broadcast
    
    echo ""
    log_info "🎉 All tests completed!"
    log_info "You can now interact with the VMs:"
    log_info "  curl http://172.16.1.2:8000/health"
    log_info "  curl http://172.16.2.2:8000/info"
    log_info "  curl http://172.16.3.2:8000/cluster-status"
}

main "$@"
EOF
    
    chmod +x test-deno-vms.sh
    log_info "Test script created: test-deno-vms.sh"
}

# Clean up
cleanup() {
    log_step "Cleaning up..."
    rm -rf "$WORK_DIR"
    log_info "Cleanup completed"
}

# Main execution
main() {
    echo "🏗️  Firecracker + Deno VM Builder"
    echo "=================================="
    
    # Check dependencies
    local deps=("wget" "unzip" "e2fsck" "resize2fs" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency missing: $dep"
            log_info "Install with: sudo apt-get install $dep"
            exit 1
        fi
    done
    
    setup_workspace
    create_custom_rootfs
    install_deno_in_rootfs
    update_vm_config_template
    create_test_script
    cleanup
    
    echo ""
    log_info "🎉 VM image building completed!"
    log_info "📦 Custom rootfs: $CUSTOM_ROOTFS"
    log_info "📋 VM config template: vm-config-template.json"
    log_info "🧪 Test script: test-deno-vms.sh"
    echo ""
    log_info "Next steps:"
    log_info "1. Update script-optimized.sh to use the new rootfs"
    log_info "2. Start VMs with: ./script-optimized.sh 3"
    log_info "3. Test with: ./test-deno-vms.sh"
}

main "$@"