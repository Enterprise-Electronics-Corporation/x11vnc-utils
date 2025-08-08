# x11vnc-utils

A collection of utilities for setting up and managing x11vnc VNC server with NoVNC web client support.

## Features

- **x11vnc Service**: Automatic VNC server setup with support for GDM and SDDM display managers
- **NoVNC Web Client**: Browser-based VNC access with auto-reconnect functionality
- **dufs File Server**: Web file server with upload, delete, search, and archive support, authentication, and systemd integration
- **Interactive Setup**: User-friendly installation script with configuration options
- **Security Options**: Support for localhost-only or specific interface binding
- **Auto-detection**: Intelligent detection of X11 authentication and display configuration

## System Requirements

- Linux system with systemd
- x11vnc package
- Python 3 with pip
- Git
- Active X11 session with supported display manager

### Supported Display Managers

- **GDM** (GNOME Display Manager)
- **SDDM** (Simple Desktop Display Manager)

### Tested Platforms

- **OpenSUSE 15.5**
- **Rocky Linux 9** (RHEL-compatible)

## Limitations

- **No Fast User Switching**: The x11vnc wrapper does not support fast user switching. To change users, you must fully log out of your current session
- **Display Manager Support**: Only GDM and SDDM are currently supported
- **Single Session**: Designed for single-user desktop access

## Components

### Scripts

- `setup.sh` - Interactive installer for x11vnc and NoVNC services
- `install_x11vnc_gdm_sddm_service.sh` - x11vnc systemd service installer
- `install_novnc.sh` - NoVNC web client installer with configuration options
- `src/x11vnc-wrapper.sh` - Wrapper script for x11vnc with display manager support

### Web Interface

- `src/index.html` - Custom NoVNC landing page with auto-connect and styling

## Quick Start

1. **Run the interactive setup:**

   ```bash
   sudo ./setup.sh
   ```

2. **Access your desktop:**

   - Via web browser: `http://your-server-ip:8080`
   - Via VNC client: `your-server-ip:5900`

3. **Access dufs file server:**
   - Via web browser: `http://your-server-ip:8180` (or custom port)
   - Default root: `/root/Downloads` (configurable)
   - Authentication: Optional, set during setup

## Manual Installation

### Install x11vnc Service Only

```bash
sudo ./install_x11vnc_gdm_sddm_service.sh
```

### Install NoVNC Web Client Only

```bash
# Default configuration (all interfaces, port 8080)
sudo ./install_novnc.sh

# Localhost only (secure)
sudo ./install_novnc.sh --localhost

# Custom port and interface
sudo ./install_novnc.sh --port 9090 --interface eth0
```

### Install dufs File Server Only

```bash
# Default configuration (all interfaces, port 8180, /root/Downloads)
sudo ./install_dufs.sh

# Custom port, root, interface, and authentication
sudo ./install_dufs.sh --port 9000 --root /srv/files --interface eth0 --auth user:pass

# Uninstall dufs
sudo ./install_dufs.sh --uninstall
```

## Configuration Options

### NoVNC Installation Options

### dufs Installation Options

| Option              | Description                      | Example             |
| ------------------- | -------------------------------- | ------------------- |
| `--port PORT`       | Set dufs web port                | `--port 9000`       |
| `--root DIR`        | Set root directory to serve      | `--root /srv/files` |
| `--interface IFACE` | Bind to specific interface or IP | `--interface eth0`  |
| `--auth USER:PASS`  | Require authentication           | `--auth user:pass`  |
| `--uninstall`       | Remove dufs installation         | `--uninstall`       |

| Option              | Description                | Example            |
| ------------------- | -------------------------- | ------------------ |
| `--port PORT`       | Set NoVNC web port         | `--port 9090`      |
| `--vnc-port PORT`   | Set VNC server port        | `--vnc-port 5901`  |
| `--localhost`       | Bind to localhost only     | `--localhost`      |
| `--interface IFACE` | Bind to specific interface | `--interface eth0` |
| `--uninstall`       | Remove NoVNC installation  | `--uninstall`      |

### Security Considerations

- **Localhost binding**: Use `--localhost` for secure access requiring SSH tunneling
- **Interface binding**: Use `--interface` to limit access to specific network interfaces
- **Default**: Binds to all interfaces (accessible from network)

## Service Management

### Check Service Status

```bash
sudo systemctl status x11vnc novnc dufs
```

### View Service Logs

```bash
sudo journalctl -u x11vnc -u novnc -u dufs -f
```

### Restart Services

```bash
sudo systemctl restart x11vnc novnc dufs
```

### Uninstall All Services

To remove all x11vnc-utils services and components at once, use the provided master uninstall script:

```bash
sudo ./uninstall_all.sh
```

This will call the uninstall routines for x11vnc, NoVNC, and dufs (if present).

## SSH Tunneling (for localhost-only setups)

When NoVNC is configured for localhost-only access:

```bash
ssh -L 8080:localhost:8080 user@remote-server
```

Then access via: `http://localhost:8080`

## Troubleshooting

### Common Issues

1. **No display found**: Ensure X11 server is running and user is logged in
2. **Authentication failed**: Check X11 authentication files and permissions
3. **Port conflicts**: Verify ports 5900 and 8080 (or custom ports) are not in use
4. **Firewall**: Ensure required ports are open in firewall
5. **User switching**: Remember to fully log out before switching users (fast user switching not supported)

### Debug Commands

```bash
# Check X11 processes
ps aux | grep -E 'Xorg|gdm|sddm'

# Check listening ports
ss -tuln | grep -E ':(5900|8080)'

# Test X11 authentication
xauth list

# Check display sockets
ls -la /tmp/.X11-unix/
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
