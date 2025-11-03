#!/bin/bash

# created for running on Ubuntu 24.04.3 LTS
# HW 2013 MacBook pro
# blank the screen after 5 min and turn it off after 10 min

# Set TERM if not defined (needed for systemd service)
export TERM=${TERM:-linux}

# Apply display timeout settings
echo "Applying display timeout settings..."
echo "- Blank screen after: 5 minutes (300 seconds)"
echo "- Power down after: 10 minutes (600 seconds)"
echo "- Applied at: $(date)"

setterm --blank 5 --powerdown 10

echo "Display timeout settings have been applied successfully!"
echo ""
echo "Note: These settings apply to virtual consoles (TTY)."
echo "For graphical desktop sessions, use your desktop environment's power settings."
