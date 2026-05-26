#!/bin/bash

# Display Watchdog Uninstallation Script
# This script removes the display blanking service

set -e

SERVICE_NAME="display-watchdog"
SCRIPT_TARGET="/usr/local/bin/display-watchdog.sh"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_TARGET="/etc/systemd/system/${SERVICE_NAME}.timer"
PROFILE_TARGET="/etc/profile.d/display-watchdog.sh"

echo "Uninstalling Display Watchdog Service..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Stop and disable timer
echo "Stopping ${SERVICE_NAME} timer..."
systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || echo "Timer was not running"

echo "Disabling ${SERVICE_NAME} timer..."
systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || echo "Timer was not enabled"

# Stop the service if it's running
echo "Stopping ${SERVICE_NAME} service..."
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not running"

# Disable the service
echo "Disabling ${SERVICE_NAME} service..."
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not enabled"

# Remove timer file
if [ -f "${TIMER_TARGET}" ]; then
    echo "Removing timer file ${TIMER_TARGET}..."
    rm -f "${TIMER_TARGET}"
fi

# Remove service file
if [ -f "${SERVICE_TARGET}" ]; then
    echo "Removing service file ${SERVICE_TARGET}..."
    rm -f "${SERVICE_TARGET}"
fi

# Remove profile script
if [ -f "${PROFILE_TARGET}" ]; then
    echo "Removing profile script ${PROFILE_TARGET}..."
    rm -f "${PROFILE_TARGET}"
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