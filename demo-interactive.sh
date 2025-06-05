#!/bin/bash

# Interactive demo script for Firecracker + Deno Multi-VM setup
# This script demonstrates various VM communication patterns

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_demo() {
    echo -e "${BLUE}[DEMO]${NC} $1"
}

log_result() {
    echo -e "${CYAN}[RESULT]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

demo_header() {
    echo -e "${PURPLE}"
    echo "=============================================="
    echo "  $1"
    echo "=============================================="
    echo -e "${NC}"
}

# Wait for user input
wait_for_user() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Check if VMs are running
check_vms_ready() {
    log_info "Checking if Deno VMs are running..."
    
    local ready_count=0
    for i in {1..3}; do
        if curl -s --connect-timeout 2 "http://172.16.$i.2:8000/health" > /dev/null; then
            ready_count=$((ready_count + 1))
        fi
    done
    
    if [[ $ready_count -eq 0 ]]; then
        log_error "No Deno VMs are responding. Please start them first:"
        echo "  ./build-deno-vms.sh"
        echo "  ./script-optimized.sh deno"
        exit 1
    fi
    
    log_info "$ready_count out of 3 Deno VMs are ready"
}

# Demo 1: Health checks
demo_health_checks() {
    demo_header "Demo 1: VM Health Checks"
    
    log_demo "Each VM exposes a health endpoint that shows:"
    log_demo "- VM ID and uptime"
    log_demo "- Memory usage"
    log_demo "- System information"
    
    wait_for_user
    
    for i in {1..3}; do
        log_info "Checking health of VM $i..."
        local response=$(curl -s "http://172.16.$i.2:8000/health" | jq '.')
        
        if [[ $? -eq 0 ]]; then
            echo "$response"
            echo ""
        else
            log_error "VM $i is not responding"
        fi
    done
}

# Demo 2: VM Information
demo_vm_info() {
    demo_header "Demo 2: VM Detailed Information"
    
    log_demo "Each VM can provide detailed information about:"
    log_demo "- Available endpoints"
    log_demo "- Connected VMs"
    log_demo "- Runtime environment"
    
    wait_for_user
    
    log_info "Getting detailed info from VM 1..."
    curl -s "http://172.16.1.2:8000/info" | jq '.'
    echo ""
}

# Demo 3: Inter-VM Communication
demo_inter_vm_ping() {
    demo_header "Demo 3: Inter-VM Communication"
    
    log_demo "VMs can communicate with each other directly"
    log_demo "We'll test VM 1 pinging VM 2 and VM 3"
    
    wait_for_user
    
    log_info "VM 1 pinging VM 2..."
    local ping_result=$(curl -s "http://172.16.1.2:8000/ping/vm-2")
    echo "$ping_result" | jq '.'
    
    local success=$(echo "$ping_result" | jq -r '.success')
    if [[ "$success" == "true" ]]; then
        local response_time=$(echo "$ping_result" | jq -r '.response_time_ms')
        log_result "✅ Ping successful! Response time: ${response_time}ms"
    else
        log_error "❌ Ping failed"
    fi
    
    echo ""
    
    log_info "VM 1 pinging VM 3..."
    curl -s "http://172.16.1.2:8000/ping/vm-3" | jq '.success, .response_time_ms'
    echo ""
}

# Demo 4: Data Storage and Retrieval
demo_data_storage() {
    demo_header "Demo 4: Distributed Data Storage"
    
    log_demo "Each VM can store and retrieve data"
    log_demo "We'll store different data on different VMs"
    
    wait_for_user
    
    # Store data on VM 1
    log_info "Storing user data on VM 1..."
    curl -s -X POST "http://172.16.1.2:8000/storage/user-1" \
         -H "Content-Type: application/json" \
         -d '{
           "name": "Alice",
           "role": "developer",
           "vm": "1",
           "timestamp": "'$(date -Iseconds)'"
         }' | jq '.'
    
    echo ""
    
    # Store data on VM 2
    log_info "Storing user data on VM 2..."
    curl -s -X POST "http://172.16.2.2:8000/storage/user-2" \
         -H "Content-Type: application/json" \
         -d '{
           "name": "Bob", 
           "role": "designer",
           "vm": "2",
           "timestamp": "'$(date -Iseconds)'"
         }' | jq '.'
    
    echo ""
    
    # Retrieve data from different VMs
    log_info "Retrieving all stored data from VM 1..."
    curl -s "http://172.16.1.2:8000/storage" | jq '.'
    
    echo ""
    
    log_info "Retrieving all stored data from VM 2..."
    curl -s "http://172.16.2.2:8000/storage" | jq '.'
    
    echo ""
}

# Demo 5: Broadcast Communication
demo_broadcast() {
    demo_header "Demo 5: Broadcast Communication"
    
    log_demo "VMs can send broadcast messages to all other VMs"
    log_demo "This simulates distributed notifications or state updates"
    
    wait_for_user
    
    log_info "VM 1 broadcasting a system update message..."
    
    local broadcast_data='{
      "type": "system_update",
      "message": "New feature deployed!",
      "version": "1.2.3",
      "source": "deployment_system"
    }'
    
    local broadcast_result=$(curl -s -X POST "http://172.16.1.2:8000/broadcast" \
                           -H "Content-Type: application/json" \
                           -d "$broadcast_data")
    
    echo "$broadcast_result" | jq '.'
    
    local successful=$(echo "$broadcast_result" | jq -r '.successful')
    local total=$(echo "$broadcast_result" | jq -r '.total_targets')
    
    log_result "📡 Broadcast sent to $successful out of $total VMs"
    
    echo ""
    
    # Check if broadcast was received
    log_info "Checking if broadcast was received on VM 2..."
    curl -s "http://172.16.2.2:8000/storage/broadcast" | jq '.'
    
    echo ""
}

# Demo 6: Cluster Health Monitoring
demo_cluster_status() {
    demo_header "Demo 6: Cluster Health Monitoring"
    
    log_demo "Any VM can check the health of the entire cluster"
    log_demo "This provides a distributed monitoring capability"
    
    wait_for_user
    
    log_info "Getting cluster status from VM 1..."
    local cluster_status=$(curl -s "http://172.16.1.2:8000/cluster-status")
    
    echo "$cluster_status" | jq '.'
    
    local online_vms=$(echo "$cluster_status" | jq -r '.cluster_health.online_vms')
    local total_vms=$(echo "$cluster_status" | jq -r '.cluster_health.total_vms')
    
    log_result "🏥 Cluster Health: $online_vms/$total_vms VMs online"
    
    echo ""
}

# Demo 7: Load Balancing Simulation
demo_load_balancing() {
    demo_header "Demo 7: Load Balancing Simulation"
    
    log_demo "Simulating load balancing across multiple VMs"
    log_demo "We'll send multiple requests and round-robin between VMs"
    
    wait_for_user
    
    local vm_ips=("172.16.1.2" "172.16.2.2" "172.16.3.2")
    
    for i in {1..6}; do
        local vm_index=$(( (i - 1) % 3 ))
        local vm_ip=${vm_ips[$vm_index]}
        local vm_id=$(( vm_index + 1 ))
        
        log_info "Request #$i -> VM $vm_id ($vm_ip)"
        
        local start_time=$(date +%s%N)
        local response=$(curl -s "http://$vm_ip:8000/health")
        local end_time=$(date +%s%N)
        
        local response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
        local vm_uptime=$(echo "$response" | jq -r '.uptime_seconds')
        
        log_result "  ⚡ Response time: ${response_time}ms, VM uptime: ${vm_uptime}s"
        
        sleep 0.5
    done
    
    echo ""
}

# Demo 8: Fault Tolerance Test
demo_fault_tolerance() {
    demo_header "Demo 8: Fault Tolerance Testing"
    
    log_demo "Testing what happens when we simulate VM failures"
    log_demo "We'll check cluster status while VMs may be unavailable"
    
    wait_for_user
    
    log_info "Checking cluster status with all VMs..."
    curl -s "http://172.16.1.2:8000/cluster-status" | jq '.cluster_health'
    
    echo ""
    
    log_info "Now testing resilience - even if some VMs are slow or unavailable,"
    log_info "the remaining VMs continue to operate and report cluster status."
    
    # Test with shorter timeouts to simulate network issues
    for vm_id in {1..3}; do
        log_info "Testing VM $vm_id with short timeout..."
        
        if timeout 2s curl -s "http://172.16.$vm_id.2:8000/health" > /dev/null 2>&1; then
            log_result "  ✅ VM $vm_id responding normally"
        else
            log_result "  ⚠️  VM $vm_id slow or unavailable"
        fi
    done
    
    echo ""
}

# Main demo execution
main() {
    echo -e "${GREEN}"
    echo "🔥🦕 Firecracker + Deno Multi-VM Demo"
    echo "======================================"
    echo -e "${NC}"
    
    log_info "This interactive demo showcases:"
    log_info "✨ Multi-VM communication"
    log_info "✨ Distributed data storage"
    log_info "✨ Health monitoring"
    log_info "✨ Load balancing simulation"
    log_info "✨ Fault tolerance"
    
    echo ""
    
    check_vms_ready
    
    echo ""
    log_info "Ready to start the demo!"
    wait_for_user
    
    # Run all demos
    demo_health_checks
    demo_vm_info  
    demo_inter_vm_ping
    demo_data_storage
    demo_broadcast
    demo_cluster_status
    demo_load_balancing
    demo_fault_tolerance
    
    demo_header "Demo Complete! 🎉"
    
    log_info "The demo showcased:"
    echo "  ✅ VM health monitoring"
    echo "  ✅ Inter-VM communication"
    echo "  ✅ Distributed data storage"
    echo "  ✅ Broadcast messaging"
    echo "  ✅ Cluster health monitoring"
    echo "  ✅ Load balancing simulation"
    echo "  ✅ Fault tolerance testing"
    
    echo ""
    log_info "You can continue exploring the VMs manually:"
    echo "  curl http://172.16.1.2:8000/health"
    echo "  curl http://172.16.2.2:8000/info"
    echo "  curl http://172.16.3.2:8000/cluster-status"
    echo "  curl -X POST http://172.16.1.2:8000/storage/mykey -d '{\"test\":\"data\"}'"
    
    echo ""
    log_info "To stop the VMs:"
    echo "  ./script-optimized.sh stop"
}

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    log_error "This demo requires 'jq' for JSON parsing"
    log_info "Install with: sudo apt-get install jq"
    exit 1
fi

main "$@"