#!/bin/bash
set -e

WRAPPER_SCRIPT="/usr/local/bin/x11vnc-wrapper.sh"
SERVICE_FILE="/etc/systemd/system/x11vnc.service"

if [[ "$1" == "--uninstall" ]]; then
  echo "🔧 Uninstalling x11vnc service and script..."
  systemctl stop x11vnc.service || true
  systemctl disable x11vnc.service || true
  rm -f "$WRAPPER_SCRIPT"
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  echo "✅ x11vnc service uninstalled."
  exit 0
fi

# Check if x11vnc is installed
if ! command -v x11vnc >/dev/null 2>&1; then
    echo "ERROR: x11vnc is not installed on this system."
    echo "Please install x11vnc before running this script again."
    exit 1
fi

echo "🛠 Copying x11vnc wrapper script with GDM and SDDM support..."

cp ./src/x11vnc-wrapper.sh "$WRAPPER_SCRIPT"

chmod +x "$WRAPPER_SCRIPT"

echo "🛠 Creating systemd service..."

cat << EOF > "$SERVICE_FILE"
[Unit]
Description=x11vnc VNC Server (localhost only)
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
WantedBy=multi-user.target
EOF

echo "🔄 Reloading systemd and enabling service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable x11vnc.service
systemctl restart x11vnc.service

echo "✅ x11vnc service installed and started (localhost only)."
echo "📜 View logs: journalctl -u x11vnc.service -f"