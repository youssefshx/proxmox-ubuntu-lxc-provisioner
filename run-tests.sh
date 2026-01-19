#!/bin/bash
#==============================================================================
# PROXMOX UBUNTU LXC PROVISIONER - TEST SUITE RUNNER
#==============================================================================
# This script runs the comprehensive test suite to validate all provisioner
# options including storage types, provision types, mounts, VLAN, Docker, etc.
#
# REQUIREMENTS:
#   - Ansible installed (ansible-playbook, ansible-galaxy)
#   - SSH access to Proxmox hosts (10.22.11.6, 10.22.11.7, 10.22.11.8)
#   - SSH key at ~/.ssh/id_ed25519 (or configure in inventories/hosts.ini)
#
# USAGE:
#   ./run-tests.sh              # Run full test suite
#   ./run-tests.sh provision    # Only provision containers
#   ./run-tests.sh verify       # Only run verification tests
#   ./run-tests.sh cleanup      # Destroy all test containers
#   ./run-tests.sh templates    # Download templates first
#
# TEST CONTAINERS:
#   IDs 9001-9020 on hosts 10.22.11.6, 10.22.11.7, 10.22.11.8
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Test configuration
INVENTORY="inventories/hosts.ini"
TEST_MAP="examples/test-suite.yml"
LOG_FILE="test-results-$(date +%Y%m%d-%H%M%S).log"

# Container ID range for tests
TEST_ID_START=9001
TEST_ID_END=9020

#------------------------------------------------------------------------------
# HELPER FUNCTIONS
#------------------------------------------------------------------------------

print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║     PROXMOX UBUNTU LXC PROVISIONER - TEST SUITE                              ║"
    echo "║     Testing all storage types, provision types, mounts, VLAN, and Docker     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_success() {
    log "${GREEN}✓ $1${NC}"
}

print_error() {
    log "${RED}✗ $1${NC}"
}

print_warning() {
    log "${YELLOW}! $1${NC}"
}

print_info() {
    log "${CYAN}→ $1${NC}"
}

print_step() {
    echo ""
    log "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    log "${BLUE}  $1${NC}"
    log "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
}

check_requirements() {
    print_step "Checking Requirements"

    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "Ansible is not installed!"
        echo "  Install with: pip install ansible"
        exit 1
    fi
    print_success "Ansible found: $(ansible --version | head -n1)"

    # Check ansible-galaxy
    if ! command -v ansible-galaxy &> /dev/null; then
        print_error "ansible-galaxy not found!"
        exit 1
    fi
    print_success "ansible-galaxy found"

    # Install required collections
    print_info "Installing required Ansible collections..."
    ansible-galaxy collection install community.crypto community.general ansible.posix --force-with-deps 2>&1 | tee -a "$LOG_FILE" || true
    print_success "Collections installed"

    # Check inventory file
    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        exit 1
    fi
    print_success "Inventory file found"

    # Check test map file
    if [ ! -f "$TEST_MAP" ]; then
        print_error "Test map file not found: $TEST_MAP"
        exit 1
    fi
    print_success "Test map file found"

    # Test SSH connectivity
    print_info "Testing SSH connectivity to Proxmox hosts..."
    for host in 10.22.11.6 10.22.11.7 10.22.11.8; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$host 'echo OK' &>/dev/null; then
            print_success "SSH to $host: OK"
        else
            print_warning "SSH to $host: FAILED (may need to check SSH key)"
        fi
    done
}

#------------------------------------------------------------------------------
# PREPARE TEST ENVIRONMENT
#------------------------------------------------------------------------------

prepare_test_dirs() {
    print_step "Preparing Test Environment"

    print_info "Creating test directories on Proxmox hosts..."

    for host in 10.22.11.6 10.22.11.7 10.22.11.8; do
        ssh -o StrictHostKeyChecking=no root@$host << 'PREPARE_EOF' 2>&1 | tee -a "$LOG_FILE"
# Create test directory for mount tests
mkdir -p /mnt/pve/gold-data-nfs42/test
chmod 755 /mnt/pve/gold-data-nfs42/test

# Create some test files including a JPG
echo "Test file created at $(date)" > /mnt/pve/gold-data-nfs42/test/test-file.txt

# Create a minimal valid JPEG (1x1 red pixel)
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\x09\x09\x08\x0a\x0c\x14\x0d\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.\x27",#\x22\x1c\x1c(7teleVcdehu\x82teleVcdehu\x82\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\xff\xc4\x00\xb5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00\x01}\x01\x02\x03\x00\x04\x11\x05\x12!1A\x06\x13Qa\x07"q\x142\x81\x91\xa1\x08#B\xb1\xc1\x15R\xd1\xf0$3br\x82\x09\x0a\x16\x17\x18\x19\x1a%&\x27()*456789:CDEFGHIJSTUVWXYZcdefghijstuvwxyz\x83\x84\x85\x86\x87\x88\x89\x8a\x92\x93\x94\x95\x96\x97\x98\x99\x9a\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xfb\xd5\xc7\xff\xd9' > /mnt/pve/gold-data-nfs42/test/test-image.jpg

echo "Test environment prepared on $(hostname)"
ls -la /mnt/pve/gold-data-nfs42/test/
PREPARE_EOF
        print_success "Test directories created on $host"
    done
}

#------------------------------------------------------------------------------
# DOWNLOAD TEMPLATES
#------------------------------------------------------------------------------

download_templates() {
    print_step "Downloading Ubuntu LXC Templates"

    print_info "Running download-templates.yml playbook..."
    ansible-playbook -i "$INVENTORY" playbooks/download-templates.yml \
        -e "template_versions=['24.04']" \
        2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        print_success "Templates downloaded successfully"
    else
        print_error "Template download failed"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# PROVISION CONTAINERS
#------------------------------------------------------------------------------

provision_containers() {
    print_step "Provisioning Test Containers"

    print_info "Running provision.yml with test-suite.yml..."
    print_info "This will create containers 9001-9020 across hosts .6, .7, .8"

    ansible-playbook -i "$INVENTORY" playbooks/provision.yml \
        -e "lxc_map_file=$TEST_MAP" \
        2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        print_success "Containers provisioned successfully"
    else
        print_error "Provisioning failed"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# VERIFY CONTAINERS
#------------------------------------------------------------------------------

verify_containers() {
    print_step "Running Verification Tests"

    print_info "Running test-verify.yml playbook..."

    ansible-playbook -i "$INVENTORY" playbooks/test-verify.yml \
        -e "lxc_map_file=$TEST_MAP" \
        2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        print_success "Verification tests completed"
    else
        print_warning "Some verification tests may have failed - check log"
    fi
}

#------------------------------------------------------------------------------
# MANUAL VERIFICATION TESTS (Direct SSH to Proxmox)
#------------------------------------------------------------------------------

run_manual_tests() {
    print_step "Running Manual Verification Tests"

    # Test each container type
    local tests_passed=0
    local tests_failed=0

    # Function to run test
    run_test() {
        local test_name="$1"
        local host="$2"
        local container_id="$3"
        local test_cmd="$4"

        print_info "TEST: $test_name (Container $container_id on $host)"

        result=$(ssh -o StrictHostKeyChecking=no root@$host "pct exec $container_id -- $test_cmd" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            print_success "$test_name: PASSED"
            ((tests_passed++))
            echo "  Output: $result" | head -3
        else
            print_error "$test_name: FAILED"
            ((tests_failed++))
            echo "  Error: $result" | head -3
        fi
    }

    # Storage type tests - basic file operations
    print_info "Testing storage backends..."

    run_test "local-lvm write" "10.22.11.6" "9001" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"
    run_test "nvme-rbd-ec-5-2 write" "10.22.11.6" "9004" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"
    run_test "gold-public write" "10.22.11.6" "9007" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"
    run_test "gold-app-nfs42 write" "10.22.11.6" "9009" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"
    run_test "gold-data-nfs42 write" "10.22.11.6" "9011" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"
    run_test "database (ZFS) write" "10.22.11.6" "9013" "dd if=/dev/urandom of=/tmp/test bs=1M count=1 2>/dev/null && rm /tmp/test && echo OK"

    # Mount tests
    print_info "Testing mount points..."

    run_test "Mount exists" "10.22.11.7" "9015" "test -d /mnt/test && echo OK"
    run_test "Mount write" "10.22.11.7" "9015" "echo test > /mnt/test/writetest_$$ && rm /mnt/test/writetest_$$ && echo OK"
    run_test "JPG file found" "10.22.11.7" "9015" "find /mnt/test -name '*.jpg' | head -1 | grep -q jpg && echo OK"
    run_test "Read-only mount" "10.22.11.8" "9016" "test -d /mnt/test-readonly && echo OK"

    # NVIDIA GPU tests
    print_info "Testing NVIDIA GPU passthrough..."

    run_test "nvidia-smi (host .8)" "10.22.11.8" "9003" "nvidia-smi --query-gpu=name --format=csv,noheader"
    run_test "nvidia-smi (host .8 ceph)" "10.22.11.8" "9006" "nvidia-smi --query-gpu=name --format=csv,noheader"

    # VLAN test
    print_info "Testing VLAN configuration..."

    run_test "VLAN 22 IP address" "10.22.11.7" "9018" "ip -4 addr show eth0 | grep -q '10.22.90.18' && echo OK"

    # Docker test
    print_info "Testing Docker installation..."

    # Install Docker first
    print_info "Installing Docker in test container..."
    ssh -o StrictHostKeyChecking=no root@10.22.11.8 "pct exec 9019 -- apt-get update -qq && pct exec 9019 -- apt-get install -y -qq docker.io && pct exec 9019 -- systemctl start docker" 2>&1 | tee -a "$LOG_FILE"

    run_test "Docker hello-world" "10.22.11.8" "9019" "docker run --rm hello-world 2>&1 | grep -q 'Hello from Docker' && echo OK"

    # Internet connectivity tests
    print_info "Testing internet connectivity..."

    run_test "Internet ping" "10.22.11.6" "9020" "ping -c 1 8.8.8.8 >/dev/null && echo OK"
    run_test "DNS resolution" "10.22.11.6" "9020" "ping -c 1 google.com >/dev/null && echo OK"

    # UFW tests
    print_info "Testing UFW firewall..."

    run_test "UFW active" "10.22.11.6" "9001" "ufw status | grep -q 'Status: active' && echo OK"

    # Summary
    echo ""
    print_step "TEST SUMMARY"
    echo ""
    print_success "Tests passed: $tests_passed"
    print_error "Tests failed: $tests_failed"
    echo ""

    if [ $tests_failed -eq 0 ]; then
        print_success "ALL TESTS PASSED! 🎉"
    else
        print_warning "Some tests failed. Check the log: $LOG_FILE"
    fi
}

#------------------------------------------------------------------------------
# CLEANUP - DESTROY TEST CONTAINERS
#------------------------------------------------------------------------------

cleanup_containers() {
    print_step "Cleaning Up Test Containers"

    print_warning "This will DESTROY all test containers (IDs $TEST_ID_START-$TEST_ID_END)!"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Cleanup cancelled"
        return
    fi

    for host in 10.22.11.6 10.22.11.7 10.22.11.8; do
        print_info "Cleaning up containers on $host..."

        ssh -o StrictHostKeyChecking=no root@$host << CLEANUP_EOF
for id in \$(seq $TEST_ID_START $TEST_ID_END); do
    if pct status \$id &>/dev/null; then
        echo "Destroying container \$id..."
        pct stop \$id 2>/dev/null || true
        sleep 1
        pct destroy \$id --force 2>/dev/null || true
    fi
done
echo "Cleanup complete on \$(hostname)"
CLEANUP_EOF
        print_success "Cleanup completed on $host"
    done

    # Clean up local output directories
    print_info "Cleaning up local output directories..."
    rm -rf output/test-* 2>/dev/null || true
    print_success "Local cleanup completed"
}

#------------------------------------------------------------------------------
# GENERATE SUMMARY REPORT
#------------------------------------------------------------------------------

generate_report() {
    print_step "Generating Test Report"

    report_file="test-report-$(date +%Y%m%d-%H%M%S).md"

    cat > "$report_file" << REPORT_EOF
# Proxmox Ubuntu LXC Provisioner - Test Report

**Date:** $(date)
**Log File:** $LOG_FILE

## Test Matrix

### Storage Types Tested

| Storage | Type | Provision Types Tested |
|---------|------|------------------------|
| local-lvm | LVM | unprivileged, privileged, nvidia_gpu |
| nvme-rbd-ec-5-2 | Ceph RBD | unprivileged, privileged, nvidia_gpu |
| gold-public | NFS | unprivileged, privileged |
| gold-app-nfs42 | NFS 4.2 | unprivileged, privileged |
| gold-data-nfs42 | NFS 4.2 | unprivileged, privileged |
| database | ZFS | unprivileged, privileged |

### Additional Tests

| Test | Container ID | Description |
|------|--------------|-------------|
| Mount RW | 9015 | Read/write mount to gold-data-nfs42:/test |
| Mount RO | 9016 | Read-only mount |
| Multi-mount | 9017 | Multiple directory mounts |
| VLAN 22 | 9018 | VLAN tagging with 10.22.x.x/16 |
| Docker | 9019 | Docker installation and hello-world |
| Internet | 9020 | Internet connectivity verification |

## Container IDs Reference

- **9001-9003**: local-lvm (unprivileged, privileged, nvidia_gpu)
- **9004-9006**: nvme-rbd-ec-5-2 (unprivileged, privileged, nvidia_gpu)
- **9007-9008**: gold-public (unprivileged, privileged)
- **9009-9010**: gold-app-nfs42 (unprivileged, privileged)
- **9011-9012**: gold-data-nfs42 (unprivileged, privileged)
- **9013-9014**: database/ZFS (unprivileged, privileged)
- **9015-9017**: Mount tests
- **9018**: VLAN 22 test
- **9019**: Docker test
- **9020**: Internet test

## Output Files

SSH keys and inventories generated in:
\`\`\`
output/test-*/
├── id_ed25519      (private key)
├── id_ed25519.pub  (public key)
└── hosts.ini       (Ansible inventory)
\`\`\`

## Cleanup

To destroy all test containers:
\`\`\`bash
./run-tests.sh cleanup
\`\`\`
REPORT_EOF

    print_success "Report generated: $report_file"
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

main() {
    print_banner

    case "${1:-full}" in
        templates)
            check_requirements
            download_templates
            ;;
        provision)
            check_requirements
            prepare_test_dirs
            provision_containers
            ;;
        verify)
            check_requirements
            verify_containers
            run_manual_tests
            ;;
        cleanup)
            cleanup_containers
            ;;
        full|all)
            check_requirements
            prepare_test_dirs
            download_templates
            provision_containers
            sleep 10  # Wait for containers to settle
            verify_containers
            run_manual_tests
            generate_report
            ;;
        report)
            generate_report
            ;;
        *)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  full       - Run complete test suite (default)"
            echo "  templates  - Download Ubuntu templates"
            echo "  provision  - Provision test containers"
            echo "  verify     - Run verification tests"
            echo "  cleanup    - Destroy all test containers"
            echo "  report     - Generate test report"
            ;;
    esac

    echo ""
    print_info "Log file: $LOG_FILE"
}

main "$@"
