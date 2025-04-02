#!/bin/bash
# System Health Monitor - Installer
# This script installs the System Health Monitor tool and its dependencies

# Define color codes
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m" # No Color

# Check if running with root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This installer needs root privileges to install system-wide.${NC}"
    echo -e "Please run: ${BOLD}sudo $0${NC}"
    exit 1
fi

echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             SYSTEM HEALTH MONITOR - INSTALLER              ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# Check if script exists
if [ ! -f "system-health.sh" ]; then
    echo -e "${RED}Error: system-health.sh not found in the current directory.${NC}"
    echo "Please make sure you're running this installer from the correct directory."
    exit 1
fi

# Make script executable
chmod +x system-health.sh
echo -e "${GREEN}✓${NC} Script is now executable"

# Function to detect the package manager
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
    else
        PKG_MANAGER="unknown"
        INSTALL_CMD="echo 'Package manager not supported. Please install manually:'"
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "\n${CYAN}Installing dependencies...${NC}"
    detect_package_manager
    
    if [ "$PKG_MANAGER" = "unknown" ]; then
        echo -e "${YELLOW}Unknown package manager. Please install these dependencies manually:${NC}"
        echo -e "- bc\n- smartmontools\n- lm-sensors\n- sysstat"
        return
    fi
    
    echo -e "Using package manager: ${BOLD}$PKG_MANAGER${NC}"
    
    # Installation status flags
    bc_installed=false
    smartmontools_installed=false
    lm_sensors_installed=false
    sysstat_installed=false
    
    # Check for already installed packages
    if command -v bc >/dev/null 2>&1; then
        bc_installed=true
        echo -e "${GREEN}✓${NC} bc is already installed"
    fi
    
    if command -v smartctl >/dev/null 2>&1; then
        smartmontools_installed=true
        echo -e "${GREEN}✓${NC} smartmontools is already installed"
    fi
    
    if command -v sensors >/dev/null 2>&1; then
        lm_sensors_installed=true
        echo -e "${GREEN}✓${NC} lm-sensors is already installed"
    fi
    
    if command -v iostat >/dev/null 2>&1; then
        sysstat_installed=true
        echo -e "${GREEN}✓${NC} sysstat is already installed"
    fi
    
    # Install missing packages
    missing_packages=""
    
    # Add missing packages to the list
    if ! $bc_installed; then missing_packages="$missing_packages bc"; fi
    if ! $smartmontools_installed; then 
        if [ "$PKG_MANAGER" = "pacman" ]; then
            missing_packages="$missing_packages smartmontools"
        else
            missing_packages="$missing_packages smartmontools"
        fi
    fi
    if ! $lm_sensors_installed; then 
        if [ "$PKG_MANAGER" = "pacman" ]; then
            missing_packages="$missing_packages lm_sensors"
        else
            missing_packages="$missing_packages lm-sensors"
        fi
    fi
    if ! $sysstat_installed; then missing_packages="$missing_packages sysstat"; fi
    
    # Install only if there are missing packages
    if [ -n "$missing_packages" ]; then
        echo -e "${BLUE}Installing missing packages:${NC} $missing_packages"
        sudo $INSTALL_CMD $missing_packages
        
        # Verify installation
        echo -e "${BLUE}Verifying installation...${NC}"
        install_errors=false
        
        if ! $bc_installed && ! command -v bc >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Failed to install bc"
            install_errors=true
        elif ! $bc_installed; then
            echo -e "${GREEN}✓${NC} bc installed successfully"
        fi
        
        if ! $smartmontools_installed && ! command -v smartctl >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Failed to install smartmontools"
            install_errors=true
        elif ! $smartmontools_installed; then
            echo -e "${GREEN}✓${NC} smartmontools installed successfully"
        fi
        
        if ! $lm_sensors_installed && ! command -v sensors >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Failed to install lm-sensors"
            install_errors=true
        elif ! $lm_sensors_installed; then
            echo -e "${GREEN}✓${NC} lm-sensors installed successfully"
        fi
        
        if ! $sysstat_installed && ! command -v iostat >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Failed to install sysstat"
            install_errors=true
        elif ! $sysstat_installed; then
            echo -e "${GREEN}✓${NC} sysstat installed successfully"
        fi
        
        if $install_errors; then
            echo -e "${YELLOW}Warning: Some dependencies could not be installed.${NC}"
            echo -e "${YELLOW}The script will still work but with limited functionality.${NC}"
        else
            echo -e "${GREEN}✓${NC} All dependencies installed successfully"
        fi
    else
        echo -e "${GREEN}✓${NC} All dependencies are already installed"
    fi
}

# Install the script system-wide
install_script() {
    echo -e "\n${CYAN}Installing script to /usr/local/bin/system-health...${NC}"
    
    # Copy the script to /usr/local/bin
    cp system-health.sh /usr/local/bin/system-health
    chmod +x /usr/local/bin/system-health
    
    echo -e "${GREEN}✓${NC} Script installed successfully"
    echo -e "You can now run it from anywhere with: ${BOLD}sudo system-health${NC}"
}

# Configure Oh-My-Zsh integration (if available)
configure_oh_my_zsh() {
    echo -e "\n${CYAN}Checking for Oh-My-Zsh...${NC}"
    
    # Try to find the .zshrc file for the user who ran sudo
    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        ZSHRC="$USER_HOME/.zshrc"
    else
        ZSHRC="$HOME/.zshrc"
    fi
    
    if [ -f "$ZSHRC" ]; then
        echo -e "${GREEN}Found .zshrc at $ZSHRC${NC}"
        
        echo -e "${YELLOW}Would you like to add aliases to Oh-My-Zsh? (y/n)${NC}"
        read -r ADD_ALIASES
        
        if [[ "$ADD_ALIASES" =~ ^[Yy]$ ]]; then
            # Check if aliases already exist
            if grep -q "alias health=" "$ZSHRC"; then
                echo -e "${YELLOW}Aliases already exist in $ZSHRC${NC}"
            else
                # Add aliases to .zshrc
                echo "" >> "$ZSHRC"
                echo "# System Health Monitor aliases" >> "$ZSHRC"
                echo "alias health='sudo system-health'" >> "$ZSHRC"
                echo "alias health-fix='sudo system-health --fix'" >> "$ZSHRC"
                
                echo -e "${GREEN}✓${NC} Aliases added to $ZSHRC"
                echo -e "You can now use: ${BOLD}health${NC} or ${BOLD}health-fix${NC}"
                
                # Set proper ownership
                if [ -n "$SUDO_USER" ]; then
                    chown "$SUDO_USER:$(id -g "$SUDO_USER")" "$ZSHRC"
                fi
                
                echo -e "${YELLOW}Remember to run: source $ZSHRC${NC}"
            fi
        fi
    else
        echo -e "${BLUE}Oh-My-Zsh not detected. Skipping aliases setup.${NC}"
    fi
}

# Main installation process
echo -e "\n${BOLD}Starting installation...${NC}"

install_dependencies
install_script
configure_oh_my_zsh

echo -e "\n${BOLD}${GREEN}Installation complete!${NC}"
echo -e "Thank you for installing System Health Monitor."
echo -e "Usage:"
echo -e "  ${BOLD}sudo system-health${NC}       - Run health check"
echo -e "  ${BOLD}sudo system-health --fix${NC} - Run health check & fix issues"
echo -e "  ${BOLD}system-health --help${NC}     - Show help information"
echo -e "\nVisit ${BLUE}https://github.com/acn3to/system-health-monitor${NC} for more information." 