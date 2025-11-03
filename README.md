# WATCHDOG - Display Auto-Blanking Service

A systemd service for automatically blanking the display after a specified period of inactivity on Ubuntu systems.

## Features

- Automatically blanks the screen after 5 minutes of inactivity
- Powers down the display after 10 minutes of inactivity
- Runs as a systemd service for automatic startup
- Easy installation and uninstallation scripts
- Compatible with Ubuntu 24.04.3 LTS and similar systems

## Requirements

- Ubuntu Linux (tested on 24.04.3 LTS)
- systemd
- Root/sudo access for installation

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
- Install the systemd service file to `/etc/systemd/system/display-watchdog.service`
- Enable and start the service automatically

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

### Manual Configuration

You can also run the display script manually without installing the service:

```bash
chmod +x display.sh
./display.sh
```

## Customization

To change the timeout values, edit the `display.sh` file:

```bash
# Current settings: blank after 5min, powerdown after 10min
setterm --blank 5 --powerdown 10
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
- `install.sh` - Installation script that sets up the service
- `uninstall.sh` - Uninstallation script that removes the service
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