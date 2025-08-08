#!/bin/bash

# install_dufs.sh - Install or uninstall dufs file server as a systemd service
# Usage: sudo ./install_dufs.sh [--uninstall] [--port PORT] [--root DIR] [--interface IFACE] [--auth USER:PASS]

set -e

SERVICE_NAME="dufs.service"
DUFS_BIN="/usr/local/bin/dufs"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Uninstall
if [[ "$1" == "--uninstall" ]]; then
    print_info "Stopping dufs service if running..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    print_info "Disabling dufs service..."
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    print_info "Removing systemd service file..."
    rm -f "$SERVICE_PATH"
    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    print_info "Removing dufs binary..."
    rm -f "$DUFS_BIN"
    print_success "dufs file server uninstalled."
    exit 0
fi

# Defaults
PORT=8180
ROOT="/root/Downloads"
INTERFACE=""
AUTH=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="$2"; shift 2;;
        --root)
            ROOT="$2"; shift 2;;
        --interface)
            INTERFACE="$2"; shift 2;;
        --auth)
            AUTH="$2"; shift 2;;
        *)
            shift;;
    esac
done

# Download and extract dufs binary if not present
if ! command -v dufs >/dev/null 2>&1 && [ ! -f "$DUFS_BIN" ]; then
    print_info "Downloading latest dufs release info..."
    ARCH=$(uname -m)
    # Map arch to dufs release naming
    case "$ARCH" in
        x86_64)
            DUFS_ARCH="x86_64-unknown-linux-musl";;
        aarch64|arm64)
            DUFS_ARCH="aarch64-unknown-linux-musl";;
        *)
            print_error "Unsupported architecture: $ARCH"; exit 1;;
    esac
    # Get latest version tag from GitHub API
    DUFS_VERSION=$(curl -s https://api.github.com/repos/sigoden/dufs/releases/latest | grep '"tag_name"' | head -n1 | cut -d '"' -f4)
    if [ -z "$DUFS_VERSION" ]; then
        print_error "Could not determine latest dufs version."; exit 1
    fi
    DUFS_TAR="dufs-${DUFS_VERSION}-$DUFS_ARCH.tar.gz"
    DUFS_URL="https://github.com/sigoden/dufs/releases/download/$DUFS_VERSION/$DUFS_TAR"
    TMP_DIR=$(mktemp -d)
    print_info "Downloading $DUFS_URL ..."
    if ! curl -L "$DUFS_URL" -o "$TMP_DIR/$DUFS_TAR"; then
        print_error "Failed to download dufs release archive."; rm -rf "$TMP_DIR"; exit 1
    fi
    print_info "Extracting dufs binary..."
    if ! tar -xzf "$TMP_DIR/$DUFS_TAR" -C "$TMP_DIR"; then
        print_error "Failed to extract dufs archive."; rm -rf "$TMP_DIR"; exit 1
    fi
    # Find the dufs binary in the extracted files
    DUFS_EXTRACTED=$(find "$TMP_DIR" -type f -name dufs | head -n1)
    if [ ! -f "$DUFS_EXTRACTED" ]; then
        print_error "dufs binary not found in archive."; rm -rf "$TMP_DIR"; exit 1
    fi
    mv "$DUFS_EXTRACTED" "$DUFS_BIN"
    chmod +x "$DUFS_BIN"
    # Check if the binary is valid (not a text file)
    if ! file "$DUFS_BIN" | grep -q 'ELF'; then
        print_error "Downloaded dufs binary is not valid."; rm -f "$DUFS_BIN"; rm -rf "$TMP_DIR"; exit 1
    fi
    print_success "dufs installed to $DUFS_BIN"
    rm -rf "$TMP_DIR"
fi


# Build dufs command with correct flags
CMD="$DUFS_BIN"
# Bind address logic (must be IP address for dufs)
if [ -n "$INTERFACE" ]; then
    if [[ "$INTERFACE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Direct IPv4 address
        BIND_ADDR="$INTERFACE"
    else
        # Only allow interface names, not hostnames
        BIND_ADDR=$(ip -4 addr show "$INTERFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
        if [ -z "$BIND_ADDR" ]; then
            print_error "Could not resolve interface '$INTERFACE' to an IPv4 address."; exit 1
        fi
    fi
    CMD="$CMD --bind $BIND_ADDR:$PORT"
else
    CMD="$CMD --bind 0.0.0.0:$PORT"
fi
# Allow features
CMD="$CMD --allow-upload --allow-delete --allow-search --allow-archive"
# Auth logic (syntax: -a, --auth <rules> Add auth roles, e.g. user:pass@/dir1:rw,/dir2)
if [ -n "$AUTH" ]; then
    CMD="$CMD --auth $AUTH"
fi
# Serve path
CMD="$CMD $ROOT"

# Create systemd service file
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=dufs file server
After=network.target

[Service]
Type=simple
ExecStart=$CMD
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

print_info "Reloading systemd daemon..."
systemctl daemon-reload
print_info "Enabling dufs service..."
systemctl enable "$SERVICE_NAME"
print_info "Starting dufs service..."
systemctl restart "$SERVICE_NAME"
print_success "dufs file server installed and running on port $PORT."
