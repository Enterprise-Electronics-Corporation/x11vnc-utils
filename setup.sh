#!/bin/bash

# VNC Utils Setup Script
# Interactive installer for x11vnc and NoVNC services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to ask yes/no questions
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [ "$default" = "y" ]; then
            echo -n "$question [Y/n]: "
        else
            echo -n "$question [y/N]: "
        fi
        
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

# Function to get port input
get_port() {
    local prompt="$1"
    local default="$2"
    local port
    
    while true; do
        echo -n "$prompt [$default]: "
        read -r port
        port=${port:-$default}
        
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            echo "$port"
            return 0
        else
            print_error "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done
}

# Function to get interface input
get_interface() {
    local interface
    
    echo ""
    echo "Available network interfaces:"
    ip addr show | grep -E '^[0-9]+:' | awk '{print "  " $2}' | sed 's/:$//'
    echo ""
    
    while true; do
        echo "Network binding options:"
        echo "  1) All interfaces (default - accessible from any network)"
        echo "  2) Localhost only (secure - only accessible locally)"
        echo "  3) Specific interface (enter interface name or IP)"
        echo -n "Choose option [1]: "
        
        read -r choice
        choice=${choice:-1}
        
        case "$choice" in
            1)
                echo ""
                return 0
                ;;
            2)
                echo "localhost"
                return 0
                ;;
            3)
                echo -n "Enter interface name or IP address: "
                read -r interface
                if [ -n "$interface" ]; then
                    echo "$interface"
                    return 0
                else
                    print_error "Interface cannot be empty."
                fi
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Show banner
echo ""
echo "=================================================="
echo "        VNC Utils Interactive Setup"
echo "=================================================="
echo ""
print_info "This script will help you set up VNC remote desktop access."
echo ""

# Check for required scripts
if [ ! -f "./install_x11vnc_gdm_sddm_service.sh" ]; then
    print_error "Missing install_x11vnc_gdm_sddm_service.sh script"
    exit 1
fi

if [ ! -f "./install_novnc.sh" ]; then
    print_error "Missing install_novnc.sh script"
    exit 1
fi

# Step 1: Install x11vnc service
echo "Step 1: x11vnc VNC Server Setup"
echo "================================"
print_info "The x11vnc service provides VNC access to your desktop."
print_info "It runs automatically and handles user login/logout."
echo ""

if ask_yes_no "Install x11vnc service?" "y"; then
    print_info "Installing x11vnc service..."
    ./install_x11vnc_gdm_sddm_service.sh
    print_success "x11vnc service installed successfully!"
    
    INSTALL_NOVNC=true
else
    print_warning "Skipping x11vnc installation."
    echo ""
    if ask_yes_no "Do you want to install NoVNC web client anyway?" "n"; then
        INSTALL_NOVNC=true
    else
        print_info "Setup complete. No services were installed."
        exit 0
    fi
fi

echo ""

# Step 2: Install NoVNC (optional)
if [ "$INSTALL_NOVNC" = true ]; then
    echo "Step 2: NoVNC Web Client Setup"
    echo "==============================="
    print_info "NoVNC provides web browser access to your VNC desktop."
    print_info "No additional software needed - just open a web browser!"
    echo ""
    
    if ask_yes_no "Install NoVNC web client?" "y"; then
        # Get NoVNC configuration
        echo ""
        print_info "Configuring NoVNC..."
        
        # Get ports
        NOVNC_PORT=$(get_port "NoVNC web port" "8080")
        VNC_PORT=$(get_port "VNC server port" "5900")
        
        # Get interface binding
        echo ""
        print_info "Choose how NoVNC should be accessible:"
        INTERFACE=$(get_interface)
        
        # Build command arguments
        NOVNC_ARGS=()
        NOVNC_ARGS+=("--port" "$NOVNC_PORT")
        NOVNC_ARGS+=("--vnc-port" "$VNC_PORT")
        
        if [ -n "$INTERFACE" ]; then
            if [ "$INTERFACE" = "localhost" ]; then
                NOVNC_ARGS+=("--localhost")
            else
                NOVNC_ARGS+=("--interface" "$INTERFACE")
            fi
        fi
        
        # Install NoVNC
        echo ""
        print_info "Installing NoVNC with selected configuration..."
        ./install_novnc.sh "${NOVNC_ARGS[@]}"
        
        print_success "NoVNC web client installed successfully!"
    else
        print_warning "Skipping NoVNC installation."
    fi
fi

# Final summary
echo ""
echo "=================================================="
echo "             Setup Complete!"
echo "=================================================="

# Check what was installed
if systemctl is-enabled x11vnc.service >/dev/null 2>&1; then
    print_success "x11vnc service is installed and enabled"
    print_info "VNC server will start automatically on boot"
fi

if systemctl is-enabled novnc.service >/dev/null 2>&1; then
    print_success "NoVNC web client is installed and enabled"
    
    # Get NoVNC access info
    if systemctl is-active novnc.service >/dev/null 2>&1; then
        # Try to determine access URL
        NOVNC_PORT_ACTIVE=$(ss -tuln | grep -o ':\([0-9]*\) ' | grep -E ':80[0-9][0-9] ' | head -1 | tr -d ': ')
        if [ -n "$NOVNC_PORT_ACTIVE" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            print_info "Access your desktop at: http://$LOCAL_IP:$NOVNC_PORT_ACTIVE"
        fi
    fi
fi

echo ""
print_info "Service status:"
echo "  x11vnc:  $(systemctl is-active x11vnc.service 2>/dev/null || echo 'not installed')"
echo "  novnc:   $(systemctl is-active novnc.service 2>/dev/null || echo 'not installed')"

echo ""
print_info "Useful commands:"
echo "  Check status: sudo systemctl status x11vnc novnc"
echo "  View logs:    sudo journalctl -u x11vnc -u novnc -f"
echo "  Uninstall:    sudo ./install_x11vnc_gdm_sddm_service.sh --uninstall"
echo "                sudo ./install_novnc.sh --uninstall"

echo ""
print_success "VNC remote desktop setup is complete!"