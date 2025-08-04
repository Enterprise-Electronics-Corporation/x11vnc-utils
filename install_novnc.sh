#!/bin/bash

# Simple NoVNC installer for x11vnc service
# This script installs NoVNC web client on port 8080 with auto-reconnect

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVICE_NAME="novnc"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
NOVNC_DIR="/opt/novnc"
WEBSOCKIFY_DIR="/opt/websockify"
NOVNC_PORT=8080
VNC_PORT=5900
BIND_INTERFACE=""

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --uninstall           Remove NoVNC"
    echo "  --port PORT           Set NoVNC port (default: 8080)"
    echo "  --vnc-port PORT       Set VNC server port (default: 5900)"
    echo "  --interface IFACE     Bind to specific network interface"
    echo "  --localhost           Bind to localhost only (secure)"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Interface Examples:"
    echo "  --localhost           # Bind to 127.0.0.1 (secure)"
    echo "  --interface eth0      # Bind to eth0 interface"
    echo "  --interface wlan0     # Bind to wlan0 interface"
    echo "  --interface 10.0.1.5  # Bind to specific IP address"
    echo "  (no interface)        # Bind to all interfaces (0.0.0.0)"
    echo ""
    echo "Examples:"
    echo "  $0                            # Install on all interfaces, port 8080"
    echo "  $0 --localhost                # Install on localhost only (secure)"
    echo "  $0 --interface eth0           # Install on eth0 interface"
    echo "  $0 --port 9090 --localhost    # Port 9090, localhost only"
    echo "  $0 --uninstall                # Remove NoVNC"
    echo ""
    echo "Security Note:"
    echo "  --localhost: NoVNC only accessible from the same machine"
    echo "  --interface: NoVNC only accessible from specified interface"
    echo "  No interface: NoVNC accessible from all network interfaces"
    exit 1
}

# Function to get IP address for interface
get_interface_ip() {
    local iface="$1"
    
    # If it's already an IP address, return it
    if [[ "$iface" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$iface"
        return 0
    fi
    
    # Try to get IP from interface name
    local ip
    ip=$(ip addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    else
        echo "ERROR: Could not get IP address for interface '$iface'" >&2
        echo "Available interfaces:" >&2
        ip addr show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/:$//' >&2
        return 1
    fi
}

# Function to uninstall NoVNC
uninstall_novnc() {
    echo "Uninstalling NoVNC..."
    
    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Stopping NoVNC service..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Disabling NoVNC service..."
        systemctl disable "$SERVICE_NAME"
    fi
    
    # Remove service file
    if [ -f "$SERVICE_FILE" ]; then
        echo "Removing service file..."
        rm "$SERVICE_FILE"
    fi
    
    # Remove directories
    if [ -d "$NOVNC_DIR" ]; then
        echo "Removing NoVNC directory..."
        rm -rf "$NOVNC_DIR"
    fi
    
    if [ -d "$WEBSOCKIFY_DIR" ]; then
        echo "Removing websockify directory..."
        rm -rf "$WEBSOCKIFY_DIR"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    echo ""
    echo "NoVNC has been successfully uninstalled!"
    exit 0
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    
    # Detect package manager and install dependencies
    if command -v apt &> /dev/null; then
        apt update
        apt install -y git python3 python3-pip python3-venv iproute2
    elif command -v dnf &> /dev/null; then
        dnf install -y git python3 python3-pip iproute
    elif command -v yum &> /dev/null; then
        yum install -y git python3 python3-pip iproute
    elif command -v zypper &> /dev/null; then
        zypper install -y git python3 python3-pip iproute2
    else
        echo "ERROR: Could not detect package manager. Please install dependencies manually:"
        echo "  - git, python3, python3-pip, iproute2"
        exit 1
    fi
}

# Function to install NoVNC
install_novnc() {
    echo "Installing NoVNC and websockify..."
    
    # Create directories
    mkdir -p "$NOVNC_DIR"
    mkdir -p "$WEBSOCKIFY_DIR"
    
    # Clone NoVNC
    if [ -d "$NOVNC_DIR/.git" ]; then
        echo "Updating existing NoVNC installation..."
        cd "$NOVNC_DIR"
        git pull
    else
        echo "Cloning NoVNC..."
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    fi
    
    # Clone websockify
    if [ -d "$WEBSOCKIFY_DIR/.git" ]; then
        echo "Updating existing websockify installation..."
        cd "$WEBSOCKIFY_DIR"
        git pull
    else
        echo "Cloning websockify..."
        git clone https://github.com/novnc/websockify.git "$WEBSOCKIFY_DIR"
    fi
    
    # Create Python virtual environment for websockify
    echo "Setting up Python virtual environment..."
    cd "$WEBSOCKIFY_DIR"
    python3 -m venv venv
    # shellcheck source=/dev/null
    source venv/bin/activate
    pip install --upgrade pip
    pip install -e .
    deactivate
    
    # Copy index.html from src directory
    echo "Copying NoVNC configuration..."
    cp "$SCRIPT_DIR/src/index.html" "$NOVNC_DIR/index.html"

    echo "NoVNC configuration copied successfully"
}

# Function to create systemd service
create_service() {
    echo "Creating NoVNC systemd service..."
    
    # Find websockify executable
    local websockify_exec=""
    if [ -f "$WEBSOCKIFY_DIR/venv/bin/websockify" ]; then
        websockify_exec="$WEBSOCKIFY_DIR/venv/bin/websockify"
    elif [ -f "$WEBSOCKIFY_DIR/websockify.py" ]; then
        websockify_exec="$WEBSOCKIFY_DIR/venv/bin/python $WEBSOCKIFY_DIR/websockify.py"
    elif [ -f "$WEBSOCKIFY_DIR/websockify/websockify.py" ]; then
        websockify_exec="$WEBSOCKIFY_DIR/venv/bin/python $WEBSOCKIFY_DIR/websockify/websockify.py"
    else
        echo "ERROR: Could not find websockify executable"
        exit 1
    fi
    
    # Build the bind address and description
    local bind_addr=""
    local description="NoVNC Web Client with Auto-Reconnect"
    
    if [ -n "$BIND_INTERFACE" ]; then
        if [ "$BIND_INTERFACE" = "localhost" ]; then
            bind_addr="127.0.0.1:"
            description="$description (localhost only)"
        else
            # Get IP address for the interface
            local interface_ip
            if interface_ip=$(get_interface_ip "$BIND_INTERFACE"); then
                bind_addr="${interface_ip}:"
                description="$description (${BIND_INTERFACE}: ${interface_ip})"
            else
                exit 1
            fi
        fi
    else
        description="$description (all interfaces)"
    fi
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=$description
Documentation=https://github.com/novnc/noVNC
After=x11vnc.service network.target
Wants=x11vnc.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$WEBSOCKIFY_DIR
ExecStart=$websockify_exec --web=$NOVNC_DIR ${bind_addr}$NOVNC_PORT localhost:$VNC_PORT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=novnc

[Install]
WantedBy=default.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

# Function to install NoVNC service
install_novnc_service() {
    echo "Installing NoVNC Web Client with Auto-Reconnect..."
    
    # Determine bind configuration
    local bind_description=""
    local access_url=""
    local security_note=""
    
    if [ -n "$BIND_INTERFACE" ]; then
        if [ "$BIND_INTERFACE" = "localhost" ]; then
            bind_description="localhost only (127.0.0.1)"
            access_url="http://127.0.0.1:$NOVNC_PORT"
            security_note="🔒 Security: NoVNC only accessible from this machine"
        else
            local interface_ip
            if interface_ip=$(get_interface_ip "$BIND_INTERFACE"); then
                bind_description="$BIND_INTERFACE ($interface_ip)"
                access_url="http://$interface_ip:$NOVNC_PORT"
                security_note="🔒 Security: NoVNC only accessible from $BIND_INTERFACE interface"
            else
                exit 1
            fi
        fi
    else
        bind_description="all interfaces (0.0.0.0)"
        access_url="http://$(hostname -I | awk '{print $1}'):$NOVNC_PORT"
        security_note="⚠️  Security: NoVNC accessible from all network interfaces"
    fi
    
    echo "Configuration:"
    echo "  NoVNC Port: $NOVNC_PORT"
    echo "  VNC Port: $VNC_PORT"
    echo "  Bind Interface: $bind_description"
    echo "  Auto-Reconnect: Enabled (2s delay)"
    echo ""
    
    # Check if x11vnc service exists
    if ! systemctl list-unit-files | grep -q "x11vnc.service"; then
        echo "WARNING: x11vnc service not found."
        echo "Make sure to install x11vnc service first for this to work."
        echo ""
    fi
    
    # Install dependencies
    install_dependencies
    
    # Install NoVNC
    install_novnc
    
    # Create systemd service
    create_service
    
    # Start the service
    echo "Starting NoVNC service..."
    systemctl start "$SERVICE_NAME"
    
    # Wait and check status
    sleep 5
    
    echo ""
    echo "=== SERVICE STATUS ==="
    systemctl status "$SERVICE_NAME" --no-pager -l --lines=10
    
    echo ""
    echo "=== PORT CHECK ==="
    if ss -tuln | grep -q ":$NOVNC_PORT "; then
        echo "✅ NoVNC is listening on port $NOVNC_PORT"
        ss -tuln | grep ":$NOVNC_PORT "
    else
        echo "❌ NoVNC is not listening on port $NOVNC_PORT"
        echo ""
        echo "Recent logs:"
        journalctl -u "$SERVICE_NAME" --no-pager -l --lines=5
    fi
    
    echo ""
    echo "🎉 NoVNC Installation Complete!"
    echo ""
    echo "$security_note"
    echo ""
    echo "🌐 Access URL: $access_url"
    echo ""
    if [ "$BIND_INTERFACE" = "localhost" ]; then
        echo "SSH Tunnel: ssh -L $NOVNC_PORT:localhost:$NOVNC_PORT user@$(hostname -I | awk '{print $1}')"
        echo ""
    fi
    echo "Management:"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
    echo "  sudo $0 --uninstall"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --uninstall)
            uninstall_novnc
            ;;
        --port)
            NOVNC_PORT="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --interface)
            BIND_INTERFACE="$2"
            shift 2
            ;;
        --localhost)
            BIND_INTERFACE="localhost"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            show_usage
            ;;
    esac
done

# Validate ports
if ! [[ "$NOVNC_PORT" =~ ^[0-9]+$ ]] || [ "$NOVNC_PORT" -lt 1 ] || [ "$NOVNC_PORT" -gt 65535 ]; then
    echo "ERROR: Invalid NoVNC port: $NOVNC_PORT"
    exit 1
fi

if ! [[ "$VNC_PORT" =~ ^[0-9]+$ ]] || [ "$VNC_PORT" -lt 1 ] || [ "$VNC_PORT" -gt 65535 ]; then
    echo "ERROR: Invalid VNC port: $VNC_PORT"
    exit 1
fi

# Install NoVNC
install_novnc_service