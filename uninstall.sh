#!/bin/bash

# Display Watchdog Uninstallation Script
# This script removes the display blanking service

set -e

SERVICE_NAME="display-watchdog"
SCRIPT_TARGET="/usr/local/bin/display-watchdog.sh"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Uninstalling Display Watchdog Service..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Stop the service if it's running
echo "Stopping ${SERVICE_NAME} service..."
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not running"

# Disable the service
echo "Disabling ${SERVICE_NAME} service..."
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not enabled"

# Remove service file
if [ -f "${SERVICE_TARGET}" ]; then
    echo "Removing service file ${SERVICE_TARGET}..."
    rm -f "${SERVICE_TARGET}"
fi

# Remove script file
if [ -f "${SCRIPT_TARGET}" ]; then
    echo "Removing script file ${SCRIPT_TARGET}..."
    rm -f "${SCRIPT_TARGET}"
fi

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo ""
echo "Uninstallation completed successfully!"
echo "The display blanking service has been removed from your system."