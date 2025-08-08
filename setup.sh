#!/bin/bash

# VNC Utils Setup Script
# Interactive installer for x11vnc and NoVNC services

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

# Function to get port input - sets global variable PORT_RESULT
get_port() {
    local prompt="$1"
    local default="$2"
    local port
    while true; do
        echo -n "$prompt [$default]: "
        read -r port
        port=${port:-$default}
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            PORT_RESULT="$port"
            return 0
        else
            print_error "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done
}

# Function to get interface input - sets global variable INTERFACE_RESULT
get_interface() {
    local interface
    echo ""
    echo "Available network interfaces:"
    if command -v ip >/dev/null 2>&1; then
        timeout 5 ip -o -4 addr show 2>/dev/null | awk '
        {
            iface = $2
            ip = $4
            gsub(/\/.*/, "", ip)
            if (ip != "127.0.0.1") {
                if (iface_ips[iface] == "") {
                    iface_ips[iface] = ip
                } else {
                    iface_ips[iface] = iface_ips[iface] ", " ip
                }
            }
        }
        END {
            for (iface in iface_ips) {
                printf "  %s (%s)\n", iface, iface_ips[iface]
            }
        }' | sort
        timeout 5 ip link show 2>/dev/null | awk '
        /^[0-9]+:/ {
            iface = $2
            gsub(/:/, "", iface)
            if (iface != "lo") interfaces[iface] = 1
        }
        END {
            for (iface in interfaces) print iface
        }' | while read -r iface; do
            if ! timeout 5 ip -o -4 addr show "$iface" 2>/dev/null | grep -q "inet"; then
                echo "  $iface"
            fi
        done | sort
    else
        echo "  (ip command not available)"
    fi
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
                INTERFACE_RESULT=""
                return 0
                ;;
            2)
                INTERFACE_RESULT="localhost"
                return 0
                ;;
            3)
                echo -n "Enter interface name or IP address: "
                read -r interface
                if [ -n "$interface" ]; then
                    INTERFACE_RESULT="$interface"
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
if [ ! -f "./install_dufs.sh" ]; then
    print_error "Missing install_dufs.sh script"
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
        get_port "NoVNC web port" "8080"
        NOVNC_PORT="$PORT_RESULT"
        get_port "VNC server port" "5900"
        VNC_PORT="$PORT_RESULT"
        # Get interface binding
        echo ""
        print_info "Choose how NoVNC should be accessible:"
        get_interface
        INTERFACE="$INTERFACE_RESULT"
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

# Step 3: Install dufs file server (optional)
echo ""
echo "Step 3: dufs File Server Setup"
echo "==============================="
print_info "dufs provides a simple web file server with upload, delete, search, and archive support."
print_info "You can use it to transfer files to/from this machine via your browser."
echo ""
if ask_yes_no "Install dufs file server?" "n"; then
    # Get dufs configuration
    echo ""
    print_info "Configuring dufs..."
    # Get port
    get_port "dufs web port" "8180"
    DUFS_PORT="$PORT_RESULT"
    # Get root directory
    echo -n "Directory to serve [/root/Downloads]: "
    read -r DUFS_ROOT
    DUFS_ROOT=${DUFS_ROOT:-/root/Downloads}
    # Get interface binding
    echo ""
    print_info "Choose how dufs should be accessible:"
    get_interface
    DUFS_INTERFACE="$INTERFACE_RESULT"
    # Auth
    if ask_yes_no "Enable authentication (username/password)?" "n"; then
        echo -n "Enter username: "
        read -r DUFS_USER
        echo -n "Enter password: "
        read -r -s DUFS_PASS
        echo ""
        DUFS_AUTH="$DUFS_USER:$DUFS_PASS"
    else
        DUFS_AUTH=""
    fi
    # Call install_dufs.sh
    print_info "Installing dufs with selected configuration..."
    if [ -n "$DUFS_AUTH" ]; then
        ./install_dufs.sh --port "$DUFS_PORT" --root "$DUFS_ROOT" --interface "$DUFS_INTERFACE" --auth "$DUFS_AUTH"
    else
        ./install_dufs.sh --port "$DUFS_PORT" --root "$DUFS_ROOT" --interface "$DUFS_INTERFACE"
    fi
    print_success "dufs file server installed successfully!"
else
    print_warning "Skipping dufs installation."
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
    if systemctl is-active novnc.service >/dev/null 2>&1; then
        NOVNC_PORT_ACTIVE=$(ss -tuln | grep -o ':[0-9]* ' | grep -E ':80[0-9][0-9] ' | head -1 | tr -d ': ')
        if [ -n "$NOVNC_PORT_ACTIVE" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            print_info "Access your desktop at: http://$LOCAL_IP:$NOVNC_PORT_ACTIVE"
        fi
    fi
fi
if systemctl is-enabled dufs.service >/dev/null 2>&1; then
    print_success "dufs file server is installed and enabled"
    if systemctl is-active dufs.service >/dev/null 2>&1; then
        DUFS_PORT_ACTIVE=$(ss -tuln | grep -o ':[0-9]* ' | grep -E ':81[0-9][0-9] ' | head -1 | tr -d ': ')
        if [ -n "$DUFS_PORT_ACTIVE" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            print_info "Access your files at: http://$LOCAL_IP:$DUFS_PORT_ACTIVE"
        fi
    fi
fi

print_info "Service status:"
echo "  x11vnc:  $(systemctl is-active x11vnc.service 2>/dev/null || echo 'not installed')"
echo "  novnc:   $(systemctl is-active novnc.service 2>/dev/null || echo 'not installed')"
echo "  dufs:    $(systemctl is-active dufs.service 2>/dev/null || echo 'not installed')"


print_info "Useful commands:"
echo "  Check status: sudo systemctl status x11vnc novnc dufs"
echo "  View logs:    sudo journalctl -u x11vnc -u novnc -u dufs -f"
echo "  Uninstall:    sudo ./install_x11vnc_gdm_sddm_service.sh --uninstall"
echo "                sudo ./install_novnc.sh --uninstall"
echo "                sudo ./install_dufs.sh --uninstall"

if systemctl is-enabled novnc.service >/dev/null 2>&1; then
print_success "VNC remote desktop setup is complete!"
    print_success "NoVNC web client is installed and enabled"
    if systemctl is-active novnc.service >/dev/null 2>&1; then
        NOVNC_PORT_ACTIVE=$(ss -tuln | grep -o ':\([0-9]*\) ' | grep -E ':80[0-9][0-9] ' | head -1 | tr -d ': ')
        if [ -n "$NOVNC_PORT_ACTIVE" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            print_info "Access your desktop at: http://$LOCAL_IP:$NOVNC_PORT_ACTIVE"
        fi
    fi
fi

if systemctl is-enabled dufs.service >/dev/null 2>&1; then
    print_success "dufs file server is installed and enabled"
    if systemctl is-active dufs.service >/dev/null 2>&1; then
        DUFS_PORT_ACTIVE=$(ss -tuln | grep -o ':\([0-9]*\) ' | grep -E ':81[0-9][0-9] ' | head -1 | tr -d ': ')
        if [ -n "$DUFS_PORT_ACTIVE" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            print_info "Access your files at: http://$LOCAL_IP:$DUFS_PORT_ACTIVE"
        fi
    fi
fi

echo ""
echo ""
echo ""
