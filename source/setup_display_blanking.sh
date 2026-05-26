#!/bin/bash

# Script to setup display blanking after 2 minutes on Ubuntu Server
# This script modifies GRUB configuration to add consoleblank=120 parameter

set -e  # Exit on any error

GRUB_CONFIG="/etc/default/grub"
BACKUP_FILE="/etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)"
BLANK_TIME=120  # 2 minutes in seconds

echo "================================================"
echo "Ubuntu Server Display Blanking Setup Script"
echo "================================================"
echo "This script will configure your system to blank"
echo "the display after 2 minutes of inactivity."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (use sudo)" 
   echo "Usage: sudo $0"
   exit 1
fi

# Check if GRUB config exists
if [[ ! -f "$GRUB_CONFIG" ]]; then
    echo "Error: GRUB configuration file not found at $GRUB_CONFIG"
    echo "This script is designed for systems using GRUB bootloader."
    exit 1
fi

# Create backup
echo "Creating backup of GRUB configuration..."
cp "$GRUB_CONFIG" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Check if consoleblank is already configured
if grep -q "consoleblank=" "$GRUB_CONFIG"; then
    echo "Warning: consoleblank parameter already exists in GRUB config."
    echo "Current configuration:"
    grep "consoleblank=" "$GRUB_CONFIG"
    echo ""
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 0
    fi
    
    # Remove existing consoleblank parameter
    sed -i 's/consoleblank=[0-9]* *//g' "$GRUB_CONFIG"
    echo "Removed existing consoleblank parameter."
fi

# Function to add consoleblank to GRUB_CMDLINE_LINUX_DEFAULT
add_consoleblank() {
    local line="$1"
    # Remove the closing quote, add consoleblank, then add closing quote
    echo "$line" | sed 's/"$/ consoleblank='$BLANK_TIME'"/'
}

# Process the GRUB configuration
echo "Modifying GRUB configuration..."

# Create temporary file for processing
TEMP_FILE=$(mktemp)

while IFS= read -r line; do
    if [[ $line =~ ^GRUB_CMDLINE_LINUX_DEFAULT= ]]; then
        # This is the line we need to modify
        new_line=$(add_consoleblank "$line")
        echo "$new_line" >> "$TEMP_FILE"
        echo "Modified: $line"
        echo "     To: $new_line"
    else
        echo "$line" >> "$TEMP_FILE"
    fi
done < "$GRUB_CONFIG"

# Replace original with modified version
mv "$TEMP_FILE" "$GRUB_CONFIG"

echo ""
echo "GRUB configuration updated successfully!"
echo ""

# Show the changes
echo "Current GRUB_CMDLINE_LINUX_DEFAULT line:"
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"
echo ""

# Update GRUB
echo "Updating GRUB bootloader..."
if command -v update-grub >/dev/null 2>&1; then
    update-grub
elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "Warning: Could not find update-grub or grub-mkconfig command."
    echo "Please manually update your GRUB configuration."
    exit 1
fi

echo ""
echo "================================================"
echo "Setup completed successfully!"
echo "================================================"
echo "Changes made:"
echo "- Added 'consoleblank=120' to GRUB kernel parameters"
echo "- Updated GRUB bootloader configuration"
echo "- Created backup: $BACKUP_FILE"
echo ""
echo "The display will now blank after 2 minutes of inactivity"
echo "after you reboot your system."
echo ""
echo "To apply changes: sudo reboot"
echo ""
echo "To restore original configuration if needed:"
echo "  sudo cp $BACKUP_FILE $GRUB_CONFIG"
echo "  sudo update-grub"
echo "================================================"