#!/bin/bash

# Script to verify display blanking configuration
# This script checks if consoleblank parameter is properly configured

echo "================================================"
echo "Display Blanking Configuration Checker"
echo "================================================"

GRUB_CONFIG="/etc/default/grub"

# Check GRUB configuration
echo "Checking GRUB configuration..."
if [[ -f "$GRUB_CONFIG" ]]; then
    echo "GRUB config file: $GRUB_CONFIG"
    
    if grep -q "consoleblank=" "$GRUB_CONFIG"; then
        echo "✓ consoleblank parameter found in GRUB config:"
        grep "consoleblank=" "$GRUB_CONFIG" | while read line; do
            echo "  $line"
            # Extract the consoleblank value
            value=$(echo "$line" | grep -o 'consoleblank=[0-9]*' | cut -d'=' -f2)
            if [[ -n "$value" ]]; then
                minutes=$((value / 60))
                echo "  → Display will blank after $value seconds ($minutes minutes)"
            fi
        done
    else
        echo "✗ consoleblank parameter NOT found in GRUB config"
    fi
else
    echo "✗ GRUB config file not found"
fi

echo ""

# Check current kernel parameters (if system is already running with the config)
echo "Checking current kernel parameters..."
if [[ -f /proc/cmdline ]]; then
    if grep -q "consoleblank=" /proc/cmdline; then
        echo "✓ consoleblank is active in current kernel:"
        grep -o 'consoleblank=[0-9]*' /proc/cmdline | while read param; do
            value=$(echo "$param" | cut -d'=' -f2)
            minutes=$((value / 60))
            echo "  $param ($minutes minutes)"
        done
    else
        echo "✗ consoleblank not found in current kernel parameters"
        echo "  (This is normal if you haven't rebooted since setup)"
    fi
else
    echo "✗ Cannot read /proc/cmdline"
fi

echo ""

# Check current console blank setting
echo "Checking current console blank timeout..."
if [[ -f /sys/module/kernel/parameters/consoleblank ]]; then
    current_blank=$(cat /sys/module/kernel/parameters/consoleblank)
    echo "Current console blank timeout: $current_blank seconds"
    if [[ "$current_blank" == "120" ]]; then
        echo "✓ Console blanking is set to 2 minutes"
    elif [[ "$current_blank" == "0" ]]; then
        echo "⚠ Console blanking is disabled (0)"
    else
        minutes=$((current_blank / 60))
        echo "ℹ Console blanking is set to $current_blank seconds ($minutes minutes)"
    fi
else
    echo "✗ Cannot read console blank parameter"
fi

echo ""
echo "================================================"
echo "Summary:"
echo "================================================"

# Provide recommendations
grub_ok=false
kernel_ok=false

if grep -q "consoleblank=120" "$GRUB_CONFIG" 2>/dev/null; then
    grub_ok=true
fi

if grep -q "consoleblank=120" /proc/cmdline 2>/dev/null; then
    kernel_ok=true
fi

if $grub_ok && $kernel_ok; then
    echo "✓ Display blanking is properly configured and active"
    echo "  Your display should blank after 2 minutes of inactivity"
elif $grub_ok && ! $kernel_ok; then
    echo "⚠ Configuration is set but not active yet"
    echo "  Please reboot to activate: sudo reboot"
elif ! $grub_ok; then
    echo "✗ Configuration is missing or incorrect"
    echo "  Run the setup script: sudo ./setup_display_blanking.sh"
fi

echo "================================================"