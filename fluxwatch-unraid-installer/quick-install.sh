#!/bin/bash
#===============================================================================
#  FluxWatch Unraid One-Line Installer
#  
#  Usage: curl -sSL https://raw.githubusercontent.com/YOUR_REPO/main/quick-install.sh | bash
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GITHUB_REPO="YOUR_USERNAME/fluxwatch-unraid"
GITHUB_BRANCH="main"
TEMP_DIR="/tmp/fluxwatch-install-$$"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              FluxWatch Quick Installer for Unraid                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo bash <(curl -sSL URL)${NC}"
    exit 1
fi

# Check for Unraid
if [ ! -f /etc/unraid-version ]; then
    echo -e "${YELLOW}Warning: This doesn't appear to be Unraid.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo -e "${GREEN}Downloading FluxWatch installer...${NC}"

# Download the installer package
if command -v wget &> /dev/null; then
    wget -q "https://github.com/${GITHUB_REPO}/archive/${GITHUB_BRANCH}.zip" -O fluxwatch.zip
elif command -v curl &> /dev/null; then
    curl -sL "https://github.com/${GITHUB_REPO}/archive/${GITHUB_BRANCH}.zip" -o fluxwatch.zip
else
    echo -e "${RED}Error: wget or curl is required${NC}"
    exit 1
fi

# Extract
echo -e "${GREEN}Extracting...${NC}"
unzip -q fluxwatch.zip
cd fluxwatch-unraid-${GITHUB_BRANCH}

# Run installer
echo -e "${GREEN}Running installer...${NC}"
chmod +x install.sh
./install.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Installation complete!${NC}"
