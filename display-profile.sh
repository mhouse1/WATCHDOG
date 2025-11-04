#!/bin/bash

# Display Watchdog Profile Script
# This script applies display blanking settings on user login
# Should be sourced from /etc/profile.d/ or ~/.profile

# Only apply on TTY sessions, not SSH
if [[ -z "$SSH_CLIENT" && -z "$SSH_TTY" && -z "$SSH_CONNECTION" ]]; then
    # Check if we're on a real TTY
    if [[ $(tty 2>/dev/null) == /dev/tty* ]]; then
        # Set TERM if not defined
        export TERM=${TERM:-linux}
        
        # Apply display timeout settings silently
        setterm --blank 3 --powerdown 6 >/dev/null 2>&1
        
        # Optional: Show a brief message (remove if you don't want it)
        echo "Display will blank after 3 minutes of inactivity"
    fi
fi