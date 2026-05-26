#!/bin/bash

# Repair script for display-watchdog service

set -e

SERVICE_NAME="display-watchdog"
SCRIPT_TARGET="/usr/local/bin/display-watchdog.sh"
SERVICE_TARGET="/etc/systemd/system/display-watchdog.service"
TIMER_TARGET="/etc/systemd/system/display-watchdog.timer"
PROFILE_TARGET="/etc/profile.d/display-watchdog.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Repairing Display Watchdog Service ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Stop the timer and service if running
echo "Stopping timer and service..."
systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || echo "Timer was not running"
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || echo "Service was not running"

# Re-copy and fix the script
echo "Re-installing script with proper permissions..."
cp "${SCRIPT_DIR}/display.sh" "${SCRIPT_TARGET}"
chmod +x "${SCRIPT_TARGET}"

# Show what we installed
echo "Installed script contents:"
cat "${SCRIPT_TARGET}"
echo ""

# Update the service and timer files
echo "Updating service file..."
cp "${SCRIPT_DIR}/display-watchdog.service" "${SERVICE_TARGET}"

echo "Updating timer file..."
cp "${SCRIPT_DIR}/display-watchdog.timer" "${TIMER_TARGET}"

echo "Updating profile script..."
cp "${SCRIPT_DIR}/display-profile.sh" "${PROFILE_TARGET}"
chmod +x "${PROFILE_TARGET}"

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

echo "Enabling and starting timer..."
systemctl enable "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.timer"

echo "Running service once immediately..."
systemctl start "${SERVICE_NAME}.service"

echo "Checking timer status..."
systemctl status "${SERVICE_NAME}.timer" --no-pager

echo ""
echo "Checking service status..."
systemctl status "${SERVICE_NAME}.service" --no-pager

echo ""
echo "Recent service logs:"
journalctl -u "${SERVICE_NAME}.service" -n 5 --no-pager

echo ""
echo "Repair completed! Multiple mechanisms now ensure display blanking:"
echo "1. Timer runs every 5 minutes to reapply settings"
echo "2. Profile script applies settings on TTY login"
echo "3. Manual service execution available"
echo ""
echo "The display should blank after 3 minutes and power off after 6 minutes."