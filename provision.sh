#!/bin/bash
#==============================================================================
# PROXMOX UBUNTU LXC PROVISIONER - HELPER SCRIPT
#==============================================================================
# A convenience wrapper for common provisioning tasks.
#
# USAGE:
#   ./provision.sh [command] [options]
#
# COMMANDS:
#   templates    - Download Ubuntu LXC templates
#   provision    - Provision containers from a map file
#   test         - Test connectivity to provisioned containers
#   help         - Show this help message
#==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/inventories/hosts.ini"
OUTPUT_DIR="${SCRIPT_DIR}/output"

#------------------------------------------------------------------------------
# HELPER FUNCTIONS
#------------------------------------------------------------------------------

print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     PROXMOX UBUNTU LXC PROVISIONER                               ║"
    echo "║     SSH Key-Based • UFW Hardened • Telemetry-Free                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "${CYAN}→ $1${NC}"
}

check_requirements() {
    print_info "Checking requirements..."

    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "Ansible is not installed!"
        echo "  Install with: pip install ansible"
        exit 1
    fi
    print_success "Ansible found: $(ansible --version | head -n1)"

    # Check ansible-galaxy collections
    if ! ansible-galaxy collection list community.crypto &> /dev/null; then
        print_warning "community.crypto collection not found. Installing..."
        ansible-galaxy collection install -r "${SCRIPT_DIR}/requirements.yml"
    fi
    print_success "Required collections installed"

    # Check inventory file
    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        echo "  Please configure your Proxmox hosts in inventories/hosts.ini"
        exit 1
    fi
    print_success "Inventory file found"
}

#------------------------------------------------------------------------------
# COMMANDS
#------------------------------------------------------------------------------

cmd_templates() {
    print_banner
    print_info "Downloading Ubuntu LXC templates..."
    echo ""

    check_requirements

    # Parse additional arguments
    local extra_args=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                extra_args="$extra_args -e template_versions=['$2']"
                shift 2
                ;;
            --storage)
                extra_args="$extra_args -e template_storage=$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo ""
    print_info "Running playbook..."
    ansible-playbook -i "$INVENTORY" "${SCRIPT_DIR}/playbooks/download-templates.yml" $extra_args

    echo ""
    print_success "Template download complete!"
}

cmd_provision() {
    print_banner

    local map_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                map_file="$2"
                shift 2
                ;;
            *)
                # Assume first positional arg is the map file
                if [ -z "$map_file" ]; then
                    map_file="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate map file
    if [ -z "$map_file" ]; then
        print_error "No container map file specified!"
        echo ""
        echo "USAGE:"
        echo "  ./provision.sh provision -f examples/my-containers.yml"
        echo "  ./provision.sh provision examples/my-containers.yml"
        echo ""
        echo "EXAMPLES:"
        ls -1 "${SCRIPT_DIR}/examples/"*.yml 2>/dev/null | while read f; do
            echo "  - $(basename $f)"
        done
        exit 1
    fi

    # Check if file exists (try relative paths)
    if [ ! -f "$map_file" ]; then
        if [ -f "${SCRIPT_DIR}/$map_file" ]; then
            map_file="${SCRIPT_DIR}/$map_file"
        elif [ -f "${SCRIPT_DIR}/examples/$map_file" ]; then
            map_file="${SCRIPT_DIR}/examples/$map_file"
        else
            print_error "Container map file not found: $map_file"
            exit 1
        fi
    fi

    print_info "Container map: $map_file"
    echo ""

    check_requirements

    echo ""
    print_info "Starting provisioning..."
    ansible-playbook -i "$INVENTORY" "${SCRIPT_DIR}/playbooks/provision.yml" \
        -e "lxc_map_file=$map_file"

    echo ""
    print_success "Provisioning complete!"
    echo ""
    print_info "SSH keys and inventories are in: ${OUTPUT_DIR}/"
    echo ""
    echo "To connect to a container:"
    echo -e "  ${CYAN}ssh -i output/<hostname>/id_ed25519 ansible@<container_ip>${NC}"
    echo ""
    echo "To use with Ansible:"
    echo -e "  ${CYAN}ansible -i output/<hostname>/hosts.ini all -m ping${NC}"
}

cmd_test() {
    print_banner
    print_info "Testing connectivity to provisioned containers..."
    echo ""

    if [ ! -d "$OUTPUT_DIR" ]; then
        print_error "No containers have been provisioned yet!"
        echo "  Run: ./provision.sh provision -f <container_map.yml>"
        exit 1
    fi

    # Find all host.ini files and test them
    local found=0
    for hosts_file in "${OUTPUT_DIR}"/*/hosts.ini; do
        if [ -f "$hosts_file" ]; then
            found=$((found + 1))
            local container_dir=$(dirname "$hosts_file")
            local container_name=$(basename "$container_dir")

            print_info "Testing: $container_name"
            if ansible -i "$hosts_file" all -m ping -o 2>/dev/null; then
                print_success "$container_name: REACHABLE"
            else
                print_error "$container_name: UNREACHABLE"
            fi
            echo ""
        fi
    done

    if [ $found -eq 0 ]; then
        print_warning "No provisioned containers found in output/"
    else
        print_info "Tested $found container(s)"
    fi
}

cmd_list() {
    print_banner
    print_info "Provisioned containers:"
    echo ""

    if [ ! -d "$OUTPUT_DIR" ]; then
        print_warning "No containers have been provisioned yet."
        exit 0
    fi

    for dir in "${OUTPUT_DIR}"/*/; do
        if [ -d "$dir" ]; then
            local name=$(basename "$dir")
            local hosts_file="${dir}hosts.ini"

            if [ -f "$hosts_file" ]; then
                local ip=$(grep "ansible_host=" "$hosts_file" | head -n1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
                echo -e "  ${GREEN}●${NC} ${CYAN}$name${NC} ($ip)"
                echo "      SSH: ssh -i output/$name/id_ed25519 ansible@$ip"
            fi
        fi
    done
}

cmd_help() {
    print_banner
    echo "USAGE:"
    echo "  ./provision.sh [command] [options]"
    echo ""
    echo "COMMANDS:"
    echo -e "  ${CYAN}templates${NC}              Download Ubuntu LXC templates to Proxmox storage"
    echo "      --version <ver>    Specify version (22.04, 24.04, 25.04)"
    echo "      --storage <id>     Target storage (default: gold-public)"
    echo ""
    echo -e "  ${CYAN}provision${NC}              Provision containers from a map file"
    echo "      -f, --file <path>  Path to container map YAML file"
    echo ""
    echo -e "  ${CYAN}test${NC}                   Test connectivity to provisioned containers"
    echo ""
    echo -e "  ${CYAN}list${NC}                   List all provisioned containers"
    echo ""
    echo -e "  ${CYAN}help${NC}                   Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  # Download all Ubuntu templates"
    echo "  ./provision.sh templates"
    echo ""
    echo "  # Download only Ubuntu 24.04"
    echo "  ./provision.sh templates --version 24.04"
    echo ""
    echo "  # Provision from example file"
    echo "  ./provision.sh provision -f examples/simple-webserver.yml"
    echo ""
    echo "  # Test all provisioned containers"
    echo "  ./provision.sh test"
    echo ""
    echo "  # List provisioned containers"
    echo "  ./provision.sh list"
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

main() {
    cd "$SCRIPT_DIR"

    local command="${1:-help}"
    shift || true

    case "$command" in
        templates|download-templates|dl)
            cmd_templates "$@"
            ;;
        provision|prov|p)
            cmd_provision "$@"
            ;;
        test|ping|t)
            cmd_test "$@"
            ;;
        list|ls|l)
            cmd_list "$@"
            ;;
        help|-h|--help)
            cmd_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
