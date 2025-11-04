# WATCHDOG - Display Auto-Blanking Service

A systemd service for automatically blanking the display after a specified period of inactivity on Ubuntu systems.

## Features

- Automatically blanks the screen after 3 minutes of inactivity
- Powers down the display after 6 minutes of inactivity
- Runs as a systemd service for automatic startup
- Easy installation and uninstallation scripts
- Compatible with Ubuntu 24.04.3 LTS and similar systems

## Requirements

- Ubuntu Linux (tested on 24.04.3 LTS)
- systemd
- Root/sudo access for installation

## Compatibility

**Excellent for Ubuntu Server**: This solution works perfectly on Ubuntu Server command-line environments, especially on 2013 MacBook Pro hardware. The `setterm` command has direct control over the console display without desktop environment interference.

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/mhouse1/WATCHDOG.git
   cd WATCHDOG
   ```

2. Make the installation script executable and run it:
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

The installation script will:
- Copy the display script to `/usr/local/bin/display-watchdog.sh`
- Install the systemd service and timer files
- Install a profile script to `/etc/profile.d/display-watchdog.sh` for login-based activation
- Enable and start the timer for periodic reapplication
- Ensure settings persist across logins and system events

## Usage

Once installed, the service will automatically start on boot and configure the display timeout settings.

### Service Management Commands

```bash
# Check service status
sudo systemctl status display-watchdog

# Stop the service
sudo systemctl stop display-watchdog

# Start the service
sudo systemctl start display-watchdog

# Restart the service
sudo systemctl restart display-watchdog

# Disable automatic startup (but keep installed)
sudo systemctl disable display-watchdog

# Enable automatic startup
sudo systemctl enable display-watchdog
```

### Monitoring Display Timeout

Check current settings and status:
```bash
chmod +x status.sh
./status.sh
```

Run a countdown to see when screen should blank (TTY only):
```bash
chmod +x countdown.sh
./countdown.sh
```

**Ubuntu Server (Perfect!)**: If you're running Ubuntu Server command-line only, this works immediately - no additional configuration needed.

**SSH Sessions**: If you're connected via SSH, the display blanking affects the **physical MacBook Pro screen**, not your SSH terminal. Your SSH session stays active while the local console blanks.

**Desktop Environments**: The `setterm` command only affects virtual consoles (TTY sessions). To test on desktop systems:
1. Switch to a TTY with `Ctrl+Alt+F1` (or F2-F6)
2. Login to your account  
3. Wait 3 minutes without keyboard/mouse activity
4. Screen should blank automatically

### Server-Specific Testing

Test your Ubuntu Server setup:
```bash
chmod +x server-test.sh
./server-test.sh
```

This will verify that display blanking works correctly on your 2013 MacBook Pro Ubuntu Server.

**Note**: Display now blanks after 3 minutes instead of 5 minutes for quicker power saving.

### Manual Configuration

You can also run the display script manually without installing the service:

```bash
chmod +x display.sh
./display.sh
```

## Customization

To change the timeout values, edit the `display.sh` file:

```bash
# Current settings: blank after 3min, powerdown after 6min
setterm --blank 3 --powerdown 6
```

Change the numbers to your preferred values (in minutes), then reinstall:

```bash
sudo ./uninstall.sh
sudo ./install.sh
```

## Uninstallation

To completely remove the service:

```bash
chmod +x uninstall.sh
sudo ./uninstall.sh
```

This will:
- Stop and disable the service
- Remove all installed files
- Clean up systemd configuration

## Files Description

- `display.sh` - Main script that configures display timeout using setterm
- `display-watchdog.service` - Systemd service configuration file
- `display-watchdog.timer` - Systemd timer for periodic reapplication
- `display-profile.sh` - Profile script that applies settings on TTY login
- `install.sh` - Installation script that sets up the complete system
- `uninstall.sh` - Uninstallation script that removes all components
- `repair.sh` - Repair script for fixing broken installations
- `status.sh` - Status checker and environment detector
- `ssh-info.sh` - SSH vs console explanation tool
- `server-test.sh` - Ubuntu Server compatibility tester
- `countdown.sh` - Real-time blanking countdown
- `README.md` - This documentation file

## Compatibility

Originally created for:
- Ubuntu 24.04.3 LTS
- 2013 MacBook Pro hardware

Should work on most Ubuntu and Debian-based systems with systemd.

## Troubleshooting

### Service failing to start (Error 203/EXEC)
If you see "Failed to execute" errors, try the repair script:
```bash
sudo ./repair.sh
```

Or run the test script to diagnose issues:
```bash
chmod +x test.sh
./test.sh
```

Common causes:
- Missing shebang line in script
- Script not executable
- Path issues

### Service not starting
Check the service logs:
```bash
sudo journalctl -u display-watchdog -f
```

View recent service status:
```bash
systemctl status display-watchdog.service
```

### Display settings not applying
The `setterm` command works on virtual consoles (TTY). If you're using a graphical desktop environment, you might need additional tools like `xset` for X11 or appropriate Wayland tools.

For X11 systems, you might want to modify `display.sh` to include:
```bash
# For X11 desktop environments
if [ -n "$DISPLAY" ]; then
    xset dpms 300 600 900  # standby, suspend, off (in seconds)
fi
```

### Permission issues
Ensure the installation script is run with sudo privileges.

### Quick Fix Commands
```bash
# Test the installation
./test.sh

# Repair a broken installation
sudo ./repair.sh

# Manual script test
sudo /usr/local/bin/display-watchdog.sh

# Check if script is executable
ls -la /usr/local/bin/display-watchdog.sh
```

## License

This project is open source. Feel free to modify and distribute.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Support

For issues and questions, please open an issue on the GitHub repository.