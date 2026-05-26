#!/bin/bash

# Display Watchdog Installation Script
# This script installs the display blanking service as a systemd service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="display-watchdog"
SCRIPT_TARGET="/usr/local/bin/display-watchdog.sh"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Installing Display Watchdog Service..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Copy the display script to /usr/local/bin/
echo "Copying display script to ${SCRIPT_TARGET}..."
cp "${SCRIPT_DIR}/display.sh" "${SCRIPT_TARGET}"
chmod +x "${SCRIPT_TARGET}"

# Verify the script is executable and has proper shebang
echo "Verifying script installation..."
if [[ ! -x "${SCRIPT_TARGET}" ]]; then
    echo "ERROR: Script ${SCRIPT_TARGET} is not executable!"
    exit 1
fi

if ! head -n 1 "${SCRIPT_TARGET}" | grep -q "^#!/"; then
    echo "ERROR: Script ${SCRIPT_TARGET} missing shebang line!"
    exit 1
fi

# Copy the systemd service and timer files
echo "Installing systemd service to ${SERVICE_TARGET}..."
cp "${SCRIPT_DIR}/${SERVICE_NAME}.service" "${SERVICE_TARGET}"

TIMER_TARGET="/etc/systemd/system/${SERVICE_NAME}.timer"
echo "Installing systemd timer to ${TIMER_TARGET}..."
cp "${SCRIPT_DIR}/${SERVICE_NAME}.timer" "${TIMER_TARGET}"

# Install profile script for login-based activation
PROFILE_TARGET="/etc/profile.d/display-watchdog.sh"
echo "Installing profile script to ${PROFILE_TARGET}..."
cp "${SCRIPT_DIR}/display-profile.sh" "${PROFILE_TARGET}"
chmod +x "${PROFILE_TARGET}"

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the timer (not the service directly)
echo "Enabling ${SERVICE_NAME} timer..."
systemctl enable "${SERVICE_NAME}.timer"

echo "Starting ${SERVICE_NAME} timer..."
systemctl start "${SERVICE_NAME}.timer"

# Also run the service once immediately
echo "Running initial setup..."
systemctl start "${SERVICE_NAME}.service"

# Check timer status
echo "Timer status:"
systemctl status "${SERVICE_NAME}.timer" --no-pager

echo ""
echo "Service status:"
systemctl status "${SERVICE_NAME}.service" --no-pager

echo ""
echo "Installation completed successfully!"
echo "The display will now blank after 5 minutes of inactivity and power down after 10 minutes."
echo ""
echo "Useful commands:"
echo "  Check timer:     sudo systemctl status ${SERVICE_NAME}.timer"
echo "  Check service:   sudo systemctl status ${SERVICE_NAME}"
echo "  Stop timer:      sudo systemctl stop ${SERVICE_NAME}.timer"
echo "  Start timer:     sudo systemctl start ${SERVICE_NAME}.timer"
echo "  Disable timer:   sudo systemctl disable ${SERVICE_NAME}.timer"
echo "  Manual run:      sudo systemctl start ${SERVICE_NAME}"
echo "  Uninstall:       sudo ./uninstall.sh"
echo ""
echo "Note: Settings are also applied automatically on TTY login via /etc/profile.d/display-watchdog.sh"