# Firecracker Multi-VM Demo Makefile

.PHONY: help setup test start stop status clean

# Default target
help:
	@echo "Firecracker Multi-VM Demo Commands:"
	@echo ""
	@echo "  make setup     - Setup Firecracker environment (run once)"
	@echo "  make test      - Test the setup"
	@echo "  make start     - Start 3 VMs (default)"
	@echo "  make start N=5 - Start 5 VMs"
	@echo "  make stop      - Stop all VMs"
	@echo "  make status    - Check VM status"
	@echo "  make clean     - Clean all generated files"
	@echo "  make help      - Show this help"

# Setup environment
setup:
	@echo "Setting up Firecracker environment..."
	chmod +x setup.sh script.sh test.sh
	./setup.sh

# Test setup
test:
	@echo "Testing Firecracker setup..."
	./test.sh

# Start VMs (default 3, or specify with N=5)
start:
	@echo "Starting VMs..."
	./script.sh $(or $(N),3)

# Stop all VMs
stop:
	@echo "Stopping all VMs..."
	./script.sh stop

# Check VM status
status:
	@echo "Checking VM status..."
	./script.sh status

# Clean all generated files
clean:
	@echo "Cleaning up..."
	./script.sh stop 2>/dev/null || true
	rm -rf vms/ logs/ sockets/
	rm -f vmlinux rootfs.ext4
	@echo "Cleanup complete"

# Restart VMs
restart: stop
	@sleep 2
	@$(MAKE) start N=$(or $(N),3)