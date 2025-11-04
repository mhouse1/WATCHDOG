#!/bin/bash

# created for running on Ubuntu 24.04.3 LTS
# HW 2013 MacBook pro
# blank the screen after 3 min and turn it off after 6 min

# Set TERM if not defined (needed for systemd service)
export TERM=${TERM:-linux}

# Apply display timeout settings
echo "Applying display timeout settings..."
echo "- Blank screen after: 3 minutes (180 seconds)"
echo "- Power down after: 6 minutes (360 seconds)"
echo "- Applied at: $(date)"

setterm --blank 3 --powerdown 6

echo "Display timeout settings have been applied successfully!"
echo ""
echo "Note: These settings apply to virtual consoles (TTY)."
echo "For graphical desktop sessions, use your desktop environment's power settings."
