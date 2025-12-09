#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WRAPPER_SCRIPT="/usr/local/bin/x0vncserver-wrapper.sh"
SERVICE_FILE="/etc/systemd/system/x0vncserver.service"

if [[ "$1" == "--uninstall" ]]; then
  echo "🔧 Uninstalling x0vncserver service and script..."
  systemctl stop x0vncserver.service || true
  systemctl disable x0vncserver.service || true
  rm -f "$WRAPPER_SCRIPT"
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  echo "✅ x0vncserver service uninstalled."
  exit 0
fi

# Check if x0vncserver is installed
if ! command -v x0vncserver >/dev/null 2>&1; then
    echo "ERROR: x0vncserver is not installed on this system."
    echo "Please install x0vncserver (TigerVNC) before running this script again."
    exit 1
fi

echo "🛠 Copying x0vncserver wrapper script with GDM and SDDM support..."

cp "$SCRIPT_DIR/src/x11vnc-wrapper.sh" "$WRAPPER_SCRIPT"

chmod +x "$WRAPPER_SCRIPT"

echo "🛠 Creating systemd service..."

cat << EOF > "$SERVICE_FILE"
[Unit]
Description=x0vncserver VNC Server (localhost only)
After=display-manager.service graphical.target
Requires=display-manager.service

[Service]
ExecStart=$WRAPPER_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=graphical.target
EOF

echo "🔄 Reloading systemd and enabling service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable x0vncserver.service
systemctl restart x0vncserver.service

echo "✅ x0vncserver service installed and started (localhost only)."
echo "📜 View logs: journalctl -u x0vncserver.service -f"