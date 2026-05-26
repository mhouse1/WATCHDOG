# WATCHDOG

Display blanking automation toolkit for Linux console environments.

WATCHDOG currently includes two approaches:

- Runtime `setterm` workflow (service + timer + profile hook), default values 3 min blank / 6 min powerdown.
- Kernel boot-parameter workflow (`consoleblank=120`), default value 2 min blank after reboot.

## Repository Layout

- `source/` contains all scripts and systemd unit files.
- `docs/` contains architecture and review documentation.

## Requirements

- Linux distribution with `systemd`.
- `bash` and standard GNU userland tools.
- `setterm` (from util-linux) for runtime blanking workflow.
- Root privileges for install/uninstall/setup operations.

## Quick Start (Runtime setterm workflow)

```bash
cd source
sudo ./install.sh
```

What install does:

- Installs runtime script to `/usr/local/bin/display-watchdog.sh`.
- Installs systemd unit files under `/etc/systemd/system/`.
- Installs login hook at `/etc/profile.d/display-watchdog.sh`.
- Enables and starts `display-watchdog.timer`.
- Runs service once immediately.

## Service Operations

```bash
sudo systemctl status display-watchdog.timer
sudo systemctl status display-watchdog.service

sudo systemctl start display-watchdog.timer
sudo systemctl stop display-watchdog.timer
sudo systemctl restart display-watchdog.service
```

## Diagnostics and Helpers

Run from `source/`:

```bash
./status.sh
./ssh-info.sh
./countdown.sh
./server-test.sh
```

## Alternate Workflow: Kernel `consoleblank`

If you prefer boot-time kernel blanking:

```bash
cd source
sudo ./setup_display_blanking.sh
sudo reboot
```

Verify:

```bash
cd source
./check_display_blanking.sh
```

## Behavior Notes

- Runtime `setterm` behavior targets virtual consoles (TTY), not desktop display managers.
- SSH activity does not prevent blanking of the physical local display.
- Desktop sessions generally require desktop-native power settings.

## Uninstall and Repair

From `source/`:

```bash
sudo ./uninstall.sh
sudo ./repair.sh
```

## Known Gaps

- Timeout defaults are not yet unified between runtime workflow (3/6 min) and kernel workflow (2 min).
- No formal CI test suite is included yet.

## Documentation

- Architecture: `docs/ARCHITECTURE.md`
- Latest review cycle: `docs/code-review/001-2026-05.md`

## Contributing

Follow project contribution guidance in `CONTRIBUTING.md` and repository rules in `AGENTS.md`.