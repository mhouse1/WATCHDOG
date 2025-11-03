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

# Copy the systemd service file
echo "Installing systemd service to ${SERVICE_TARGET}..."
cp "${SCRIPT_DIR}/${SERVICE_NAME}.service" "${SERVICE_TARGET}"

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service
echo "Enabling ${SERVICE_NAME} service..."
systemctl enable "${SERVICE_NAME}.service"

# Start the service
echo "Starting ${SERVICE_NAME} service..."
systemctl start "${SERVICE_NAME}.service"

# Check service status
echo "Service status:"
systemctl status "${SERVICE_NAME}.service" --no-pager

echo ""
echo "Installation completed successfully!"
echo "The display will now blank after 5 minutes of inactivity and power down after 10 minutes."
echo ""
echo "Useful commands:"
echo "  Check status:    sudo systemctl status ${SERVICE_NAME}"
echo "  Stop service:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Start service:   sudo systemctl start ${SERVICE_NAME}"
echo "  Disable service: sudo systemctl disable ${SERVICE_NAME}"
echo "  Uninstall:       sudo ./uninstall.sh"