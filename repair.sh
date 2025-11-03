#!/bin/bash

# Repair script for display-watchdog service

set -e

SERVICE_NAME="display-watchdog"
SCRIPT_TARGET="/usr/local/bin/display-watchdog.sh"
SERVICE_TARGET="/etc/systemd/system/display-watchdog.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Repairing Display Watchdog Service ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Stop the service if it's running
echo "Stopping service..."
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not running"

# Re-copy and fix the script
echo "Re-installing script with proper permissions..."
cp "${SCRIPT_DIR}/display.sh" "${SCRIPT_TARGET}"
chmod +x "${SCRIPT_TARGET}"

# Show what we installed
echo "Installed script contents:"
cat "${SCRIPT_TARGET}"
echo ""

# Update the service file
echo "Updating service file..."
cp "${SCRIPT_DIR}/display-watchdog.service" "${SERVICE_TARGET}"

# Verify the script
echo "Verifying script..."
if [[ ! -x "${SCRIPT_TARGET}" ]]; then
    echo "ERROR: Script is still not executable!"
    exit 1
fi

# Test the script
echo "Testing script execution..."
"${SCRIPT_TARGET}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: Script test failed!"
    exit 1
fi

# Reload systemd and restart service
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Starting service..."
systemctl start "${SERVICE_NAME}.service"

echo "Checking service status..."
systemctl status "${SERVICE_NAME}.service" --no-pager

echo ""
echo "Recent service logs:"
journalctl -u "${SERVICE_NAME}.service" -n 5 --no-pager

echo ""
echo "Repair completed! Service should now be working."
echo "The display should blank after 5 minutes and power off after 10 minutes."