#!/bin/bash

# Display Watchdog Status Script
# Shows current display timeout settings and provides monitoring tools

echo "=== Display Watchdog Status ==="
echo ""

# Check if setterm settings are active
echo "Current display timeout settings:"
echo "- Blank timeout: 5 minutes (300 seconds)"
echo "- Powerdown timeout: 10 minutes (600 seconds)"
echo ""

# Check service status
echo "Service Status:"
systemctl is-active display-watchdog.service --quiet && echo "✓ display-watchdog service is running" || echo "✗ display-watchdog service is not running"
echo ""

# Show when service was last started (when settings were applied)
LAST_START=$(systemctl show display-watchdog.service --property=ActiveEnterTimestamp --value)
if [[ -n "$LAST_START" && "$LAST_START" != "n/a" ]]; then
    echo "Settings last applied: $LAST_START"
    
    # Calculate time since last application
    LAST_START_EPOCH=$(date -d "$LAST_START" +%s 2>/dev/null || echo "0")
    CURRENT_EPOCH=$(date +%s)
    TIME_SINCE=$((CURRENT_EPOCH - LAST_START_EPOCH))
    
    if [[ $TIME_SINCE -gt 0 ]]; then
        echo "Time since settings applied: ${TIME_SINCE} seconds ago"
    fi
else
    echo "Settings application time: Unknown"
fi
echo ""

# Note about console vs desktop environment
echo "Important Notes:"
echo "• setterm only affects virtual consoles (TTY), not graphical desktop sessions"
echo "• For desktop environments, display blanking is usually controlled by:"
echo "  - GNOME: Settings → Privacy → Screen Lock"
echo "  - KDE: System Settings → Power Management → Energy Saving"
echo "  - XFCE: Settings → Power Manager → Display"
echo ""

# Check if we're in a graphical environment
if [[ -n "$DISPLAY" ]]; then
    echo "Current environment: Graphical desktop session (DISPLAY=$DISPLAY)"
    echo "• setterm settings may not apply here"
    echo "• Check your desktop environment's power/display settings"
    
    # Try to show X11 display power management settings if available
    if command -v xset >/dev/null 2>&1; then
        echo ""
        echo "X11 Display Power Management (if available):"
        xset q 2>/dev/null | grep -A 3 "DPMS" || echo "  DPMS information not available"
    fi
else
    echo "Current environment: Console/TTY session"
    echo "• setterm settings should apply here"
fi

echo ""
echo "To monitor in real-time:"
echo "• Switch to a TTY (Ctrl+Alt+F1-F6) to see setterm effects"
echo "• Run: watch -n 1 'date; uptime'"
echo "• For desktop: check your desktop environment's screensaver/power settings"