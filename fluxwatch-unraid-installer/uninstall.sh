#!/bin/bash
#===============================================================================
#  FluxWatch Unraid Uninstaller
#  Version: 1.0.1
#
#  Completely removes FluxWatch from Unraid
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CONTAINER_NAME="fluxwatch"
IMAGE_NAME="fluxwatch"
SHARE_PATH="/mnt/user/fluxwatch"

print_header() {
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║               FluxWatch Uninstaller                              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

confirm_uninstall() {
    echo -e "${YELLOW}This will completely remove FluxWatch from your system.${NC}"
    echo ""
    echo "The following will be removed:"
    echo "  - FluxWatch Docker container"
    echo "  - FluxWatch Docker images"
    echo "  - FluxWatch share and all data at ${SHARE_PATH}"
    echo "  - FluxWatch autostart entries"
    echo "  - FluxWatch log files"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
}

remove_container() {
    echo -e "${CYAN}Stopping and removing FluxWatch container...${NC}"
    
    # Stop container
    docker stop "${CONTAINER_NAME}" 2>/dev/null && echo -e "${GREEN}✓${NC} Container stopped" || true
    
    # Remove container
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null && echo -e "${GREEN}✓${NC} Container removed" || true
    
    # Also check for other FluxWatch/DeviceMonitor containers
    for container in $(docker ps -a --format '{{.Names}}' | grep -Ei "fluxwatch|devicemonitor" 2>/dev/null || true); do
        docker stop "$container" 2>/dev/null || true
        docker rm -f "$container" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Removed additional container: $container"
    done
}

remove_images() {
    echo -e "${CYAN}Removing FluxWatch Docker images...${NC}"
    
    for image in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -Ei "fluxwatch|devicemonitor" 2>/dev/null || true); do
        docker rmi -f "$image" 2>/dev/null && echo -e "${GREEN}✓${NC} Removed image: $image" || true
    done
    
    # Remove dangling images
    docker image prune -f 2>/dev/null || true
}

remove_files() {
    echo -e "${CYAN}Removing FluxWatch files and directories...${NC}"
    
    local paths=(
        "$SHARE_PATH"
        "/mnt/user/appdata/fluxwatch"
        "/mnt/cache/appdata/fluxwatch"
        "/boot/config/plugins/fluxwatch"
        "/var/log/fluxwatch"
        "/var/log/fluxwatch-install.log"
    )
    
    for path in "${paths[@]}"; do
        if [ -d "$path" ] || [ -f "$path" ]; then
            rm -rf "$path" 2>/dev/null && echo -e "${GREEN}✓${NC} Removed: $path" || true
        fi
    done
}

remove_autostart() {
    echo -e "${CYAN}Removing autostart entries...${NC}"
    
    if [ -f "/boot/config/go" ]; then
        if grep -q "fluxwatch" /boot/config/go 2>/dev/null; then
            sed -i '/fluxwatch/Id' /boot/config/go 2>/dev/null
            sed -i '/# FluxWatch/d' /boot/config/go 2>/dev/null
            echo -e "${GREEN}✓${NC} Removed autostart entries from /boot/config/go"
        fi
    fi
}

print_complete() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           FluxWatch has been completely removed!                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    print_header
    check_root
    confirm_uninstall
    
    echo ""
    remove_container
    remove_images
    remove_files
    remove_autostart
    
    print_complete
}

main "$@"
