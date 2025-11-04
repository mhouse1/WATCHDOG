#!/bin/bash

# Display Blanking Countdown
# Shows a countdown to when the screen should blank (for TTY/console only)

BLANK_SECONDS=180  # 3 minutes
POWERDOWN_SECONDS=360  # 6 minutes

echo "=== Display Blanking Countdown ==="
echo "This countdown is only accurate for TTY/console sessions."
echo "Press Ctrl+C to stop the countdown."
echo ""

# Function to show time in MM:SS format
format_time() {
    local total_seconds=$1
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    printf "%02d:%02d" $minutes $seconds
}

# Countdown loop
for ((i=BLANK_SECONDS; i>=0; i--)); do
    if [ $i -eq 0 ]; then
        echo -e "\r\033[KScreen should blank NOW!"
        break
    elif [ $i -le 60 ]; then
        # Show in red for last minute
        echo -e "\r\033[K\033[31mScreen will blank in: $(format_time $i)\033[0m"
    else
        echo -e "\r\033[KScreen will blank in: $(format_time $i)"
    fi
    
    # Show powerdown countdown too
    if [ $i -le $POWERDOWN_SECONDS ]; then
        powerdown_remaining=$((POWERDOWN_SECONDS - (BLANK_SECONDS - i)))
        if [ $powerdown_remaining -gt 0 ]; then
            echo -e "\033[90m(Power down in: $(format_time $powerdown_remaining))\033[0m"
        fi
    fi
    
    sleep 1
done

echo ""
echo "Countdown complete!"
echo ""
echo "Note: Actual blanking depends on:"
echo "• Being in a TTY session (not desktop)"
echo "• No keyboard/mouse activity"
echo "• setterm settings being properly applied"