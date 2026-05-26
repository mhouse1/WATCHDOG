#!/usr/bin/env bash

# Offline Ubuntu Server diagnostics collector.
# Designed for root execution and USB-targeted output bundles.

set -u
set -o pipefail

SCRIPT_NAME="collect-diagnostics.sh"
SCRIPT_VERSION="0.1.0"

DEFAULT_CMD_TIMEOUT=30
DEFAULT_LONG_TIMEOUT=120
DEFAULT_MAX_FILE_BYTES=$((50 * 1024 * 1024))
DEFAULT_MAX_JOURNAL_LINES=20000

CMD_TIMEOUT="${DEFAULT_CMD_TIMEOUT}"
LONG_TIMEOUT="${DEFAULT_LONG_TIMEOUT}"
MAX_FILE_BYTES="${DEFAULT_MAX_FILE_BYTES}"
MAX_JOURNAL_LINES="${DEFAULT_MAX_JOURNAL_LINES}"
OUTPUT_ROOT=""

START_EPOCH="$(date +%s)"
START_ISO="$(date -Is)"
HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown-host)"
TIMESTAMP_VALUE="$(date +%Y-%m-%d_%H%M%S)"

RUN_DIR=""
SUMMARY_FILE=""
MANIFEST_FILE=""
ERRORS_FILE=""
RUN_INFO_FILE=""
EXIT_CODE_FILE=""
REDACTION_RULES_FILE=""
CONFIGS_DIR=""
COPILOT_BUNDLE_FILE=""

MANDATORY_FAILURES=0
TOTAL_ERRORS=0
TRUNCATION_COUNT=0
ARCHIVE_PATH=""

log() {
  printf '%s\n' "$*"
}

log_err() {
  printf '%s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  collect-diagnostics.sh [options]

Options:
  --output-root <path>         Explicit writable USB mount path.
  --cmd-timeout <seconds>      Per-command timeout (default: 30).
  --long-timeout <seconds>     Long-log timeout (default: 120).
  --max-file-bytes <bytes>     Max output file size before truncation (default: 52428800).
  --max-journal-lines <lines>  Journal line cap per capture (default: 20000).
  --help                       Show this help.

Exit codes:
  0  Full success (mandatory collection succeeded, archive created)
  1  Partial success (one or more mandatory commands failed, archive created)
  2  Initialization failure (not root, no writable output, cannot create output tree)
  3  Archive creation failed
EOF
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-root)
        if [[ $# -lt 2 || "${2:-}" == --* ]]; then
          log_err "Missing value for --output-root"
          exit 2
        fi
        shift
        OUTPUT_ROOT="${1:-}"
        ;;
      --cmd-timeout)
        if [[ $# -lt 2 || "${2:-}" == --* ]]; then
          log_err "Missing value for --cmd-timeout"
          exit 2
        fi
        shift
        CMD_TIMEOUT="${1:-}"
        ;;
      --long-timeout)
        if [[ $# -lt 2 || "${2:-}" == --* ]]; then
          log_err "Missing value for --long-timeout"
          exit 2
        fi
        shift
        LONG_TIMEOUT="${1:-}"
        ;;
      --max-file-bytes)
        if [[ $# -lt 2 || "${2:-}" == --* ]]; then
          log_err "Missing value for --max-file-bytes"
          exit 2
        fi
        shift
        MAX_FILE_BYTES="${1:-}"
        ;;
      --max-journal-lines)
        if [[ $# -lt 2 || "${2:-}" == --* ]]; then
          log_err "Missing value for --max-journal-lines"
          exit 2
        fi
        shift
        MAX_JOURNAL_LINES="${1:-}"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown argument: $1"
        usage
        exit 2
        ;;
    esac
    shift
  done

  if ! is_integer "$CMD_TIMEOUT" || ! is_integer "$LONG_TIMEOUT" || ! is_integer "$MAX_FILE_BYTES" || ! is_integer "$MAX_JOURNAL_LINES"; then
    log_err "Timeout/limit options must be positive integers."
    exit 2
  fi
}

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_err "This script must be run as root."
    exit 2
  fi
}

is_writable_dir() {
  local candidate="$1"
  [[ -d "$candidate" && -w "$candidate" ]] || return 1
  local probe="$candidate/.watchdog_diag_write_test_$$"
  if : > "$probe" 2>/dev/null; then
    rm -f "$probe" 2>/dev/null || true
    return 0
  fi
  return 1
}

discover_usb_candidates() {
  local bases=("/media" "/run/media" "/mnt")
  local base
  local mountpoint

  for base in "${bases[@]}"; do
    [[ -d "$base" ]] || continue
    while IFS= read -r mountpoint; do
      [[ -n "$mountpoint" ]] || continue
      case "$mountpoint" in
        "$base"/*|"$base")
          if is_writable_dir "$mountpoint" && is_removable_mount "$mountpoint"; then
            printf '%s\n' "$mountpoint"
          fi
          ;;
      esac
    done < <(findmnt -rn -o TARGET 2>/dev/null || true)
  done | awk '!seen[$0]++'
}

is_removable_mount() {
  local target="$1"
  local source real_source dev_name parent_name transport rm_flag sysfs_val

  source="$(findmnt -rn -o SOURCE --target "$target" 2>/dev/null || true)"
  [[ -n "$source" ]] || return 1
  [[ "$source" == /dev/* ]] || return 1

  # Resolve symlinks such as /dev/disk/by-uuid/... and /dev/disk/by-id/...
  if [[ -L "$source" ]]; then
    real_source="$(readlink -f "$source" 2>/dev/null || echo "$source")"
  else
    real_source="$source"
  fi
  [[ "$real_source" == /dev/* ]] || return 1

  # Derive parent device name from partition paths:
  #   /dev/sdb1  -> sdb     /dev/sdb  -> sdb
  #   /dev/nvme0n1p1 -> nvme0n1       /dev/mmcblk0p1 -> mmcblk0
  dev_name="${real_source##*/}"
  parent_name="$dev_name"
  if [[ "$dev_name" =~ ^(sd[a-z]+)[0-9]+$ ]]; then
    parent_name="${BASH_REMATCH[1]}"
  elif [[ "$dev_name" =~ ^(nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
    parent_name="${BASH_REMATCH[1]}"
  elif [[ "$dev_name" =~ ^(mmcblk[0-9]+)p[0-9]+$ ]]; then
    parent_name="${BASH_REMATCH[1]}"
  fi

  if command -v lsblk >/dev/null 2>&1; then
    # TRAN=usb is the most reliable indicator; some drives report RM=0 even on USB
    transport="$(lsblk -ndo TRAN "/dev/${parent_name}" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
    [[ "$transport" == "usb" ]] && return 0

    # Fallback: check RM (removable) flag on parent device
    rm_flag="$(lsblk -ndo RM "/dev/${parent_name}" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
    [[ "$rm_flag" == "1" ]] && return 0
  fi

  # Fallback: check sysfs removable attribute
  if [[ -f "/sys/block/${parent_name}/removable" ]]; then
    sysfs_val="$(cat "/sys/block/${parent_name}/removable" 2>/dev/null || echo 0)"
    [[ "$sysfs_val" == "1" ]] && return 0
  fi

  # Fallback: udevadm ID_BUS=usb covers UAS and USB-attached storage
  if command -v udevadm >/dev/null 2>&1; then
    udevadm info --query=property --name="/dev/${parent_name}" 2>/dev/null \
      | grep -q 'ID_BUS=usb' && return 0
  fi

  return 1
}

resolve_output_root() {
  if [[ -n "$OUTPUT_ROOT" ]]; then
    if ! is_writable_dir "$OUTPUT_ROOT"; then
      log_err "Provided output root is not writable: $OUTPUT_ROOT"
      exit 2
    fi
    return
  fi

  mapfile -t candidates < <(discover_usb_candidates)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    log_err "No writable USB-like mount found under /media, /run/media, or /mnt."
    log_err "Re-run with --output-root <path>."
    exit 2
  fi

  if [[ ${#candidates[@]} -gt 1 ]]; then
    log_err "Multiple writable mount candidates found. Re-run with --output-root:"
    local c
    for c in "${candidates[@]}"; do
      log_err "  - $c"
    done
    exit 2
  fi

  OUTPUT_ROOT="${candidates[0]}"
}

truncate_if_needed() {
  local file="$1"
  local bytes
  [[ -f "$file" ]] || return 0
  bytes="$(wc -c < "$file" 2>/dev/null || echo 0)"
  if [[ "$bytes" -gt "$MAX_FILE_BYTES" ]]; then
    tail -c "$MAX_FILE_BYTES" "$file" > "${file}.trunc" 2>/dev/null || return 0
    mv "${file}.trunc" "$file"
    TRUNCATION_COUNT=$((TRUNCATION_COUNT + 1))
    printf 'TRUNCATED|%s|size=%s|max=%s\n' "$file" "$bytes" "$MAX_FILE_BYTES" >> "$ERRORS_FILE"
  fi
}

redact_file() {
  local file="$1"
  local tmp1="${file}.redact1"
  local tmp2="${file}.redact2"
  [[ -f "$file" ]] || return 0

  # Redact MAC suffix and common serial patterns.
  sed -E \
    -e 's/([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}):[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}/\1:xx:xx:xx/g' \
    -e 's/(Serial Number[[:space:]]*:[[:space:]]*).*/\1[REDACTED]/Ig' \
    -e 's/(ID_SERIAL(_SHORT)?=).*/\1[REDACTED]/Ig' \
    -e 's/(WWN[[:space:]]*:[[:space:]]*).*/\1[REDACTED]/Ig' \
    "$file" > "$tmp1" 2>/dev/null || cp "$file" "$tmp1"

  # Redact public IPv4 addresses while preserving RFC1918 and local ranges.
  awk '
    function valid_octet(v) { return (v ~ /^[0-9]+$/ && v >= 0 && v <= 255) }
    function is_private(ip, p, a, b) {
      split(ip, p, ".")
      a = p[1] + 0
      b = p[2] + 0
      if (a == 10) return 1
      if (a == 172 && b >= 16 && b <= 31) return 1
      if (a == 192 && b == 168) return 1
      if (a == 127) return 1
      if (a == 169 && b == 254) return 1
      return 0
    }
    function valid_ipv4(ip, p, i) {
      split(ip, p, ".")
      if (length(p) != 4) return 0
      for (i = 1; i <= 4; i++) {
        if (!valid_octet(p[i])) return 0
      }
      return 1
    }
    {
      line = $0
      out = ""
      rest = line
      while (match(rest, /([0-9]{1,3}\.){3}[0-9]{1,3}/)) {
        pre = substr(rest, 1, RSTART - 1)
        ip = substr(rest, RSTART, RLENGTH)
        post = substr(rest, RSTART + RLENGTH)
        if (valid_ipv4(ip) && !is_private(ip)) {
          ip = "[REDACTED_PUBLIC_IP]"
        }
        out = out pre ip
        rest = post
      }
      print out rest
    }
  ' "$tmp1" > "$tmp2" 2>/dev/null || cp "$tmp1" "$tmp2"

  mv "$tmp2" "$file"
  rm -f "$tmp1" 2>/dev/null || true
}

record_manifest() {
  local category="$1"
  local name="$2"
  local command_text="$3"
  local start_ts="$4"
  local end_ts="$5"
  local duration="$6"
  local timeout_sec="$7"
  local rc="$8"
  local timed_out="$9"
  local outfile="${10}"
  local errfile="${11}"

  printf '%s|%s|%s|%s|%s|%s|timeout=%s|rc=%s|timed_out=%s|out=%s|err=%s|cmd=%s\n' \
    "$start_ts" "$end_ts" "$duration" "$category" "$name" "$HOSTNAME_VALUE" "$timeout_sec" "$rc" "$timed_out" "$outfile" "$errfile" "$command_text" >> "$MANIFEST_FILE"
}

run_capture() {
  local category="$1"
  local name="$2"
  local timeout_sec="$3"
  local mandatory="$4"
  local required_bin="$5"
  local command_text="$6"

  local outfile="$RUN_DIR/$category/$name.txt"
  local errfile="$RUN_DIR/$category/$name.err"
  local start_ts end_ts start_epoch end_epoch duration rc timed_out

  start_ts="$(date -Is)"
  start_epoch="$(date +%s)"
  timed_out=0
  rc=0

  : > "$outfile"
  : > "$errfile"

  if [[ -n "$required_bin" ]] && ! command -v "$required_bin" >/dev/null 2>&1; then
    printf 'Command unavailable: %s\n' "$required_bin" > "$outfile"
    printf 'MISSING_COMMAND|%s|%s|required_bin=%s\n' "$category" "$name" "$required_bin" >> "$ERRORS_FILE"
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    rc=127
    if [[ "$mandatory" -eq 1 ]]; then
      MANDATORY_FAILURES=$((MANDATORY_FAILURES + 1))
    fi
  else
    if command -v timeout >/dev/null 2>&1; then
      timeout "${timeout_sec}s" bash -c "$command_text" > "$outfile" 2> "$errfile"
      rc=$?
      if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        timed_out=1
      fi
    else
      bash -c "$command_text" > "$outfile" 2> "$errfile"
      rc=$?
    fi

    if [[ "$rc" -ne 0 ]]; then
      printf 'COMMAND_FAILED|%s|%s|rc=%s|timeout=%s|err=%s\n' "$category" "$name" "$rc" "$timed_out" "$errfile" >> "$ERRORS_FILE"
      TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
      if [[ "$mandatory" -eq 1 ]]; then
        MANDATORY_FAILURES=$((MANDATORY_FAILURES + 1))
      fi
    fi
  fi

  redact_file "$outfile"
  redact_file "$errfile"
  truncate_if_needed "$outfile"
  truncate_if_needed "$errfile"

  end_ts="$(date -Is)"
  end_epoch="$(date +%s)"
  duration="$((end_epoch - start_epoch))"

  record_manifest "$category" "$name" "$command_text" "$start_ts" "$end_ts" "$duration" "$timeout_sec" "$rc" "$timed_out" "$outfile" "$errfile"
}

ensure_output_tree() {
  RUN_DIR="$OUTPUT_ROOT/diagnostics/$HOSTNAME_VALUE/$TIMESTAMP_VALUE"

  mkdir -p "$RUN_DIR/system" "$RUN_DIR/disk" "$RUN_DIR/hardware" "$RUN_DIR/network" "$RUN_DIR/services" "$RUN_DIR/logs" "$RUN_DIR/meta" "$RUN_DIR/configs" || {
    log_err "Failed to create output tree under: $RUN_DIR"
    exit 2
  }

  SUMMARY_FILE="$RUN_DIR/summary.txt"
  MANIFEST_FILE="$RUN_DIR/manifest.txt"
  ERRORS_FILE="$RUN_DIR/errors.txt"
  RUN_INFO_FILE="$RUN_DIR/meta/run-info.txt"
  EXIT_CODE_FILE="$RUN_DIR/meta/exit-code.txt"
  REDACTION_RULES_FILE="$RUN_DIR/meta/redaction-rules.txt"
  CONFIGS_DIR="$RUN_DIR/configs"
  COPILOT_BUNDLE_FILE="$RUN_DIR/copilot-bundle.txt"

  : > "$SUMMARY_FILE"
  : > "$MANIFEST_FILE"
  : > "$ERRORS_FILE"

  cat > "$REDACTION_RULES_FILE" <<'EOF'
Default redaction rules:
- Keep first 3 octets of MAC addresses; redact last 3 octets.
- Redact public IPv4 addresses as [REDACTED_PUBLIC_IP].
- Redact common serial fields (Serial Number, ID_SERIAL, WWN).
- Do not collect SSH private key material.
EOF

  printf 'manifest_format=v1\n' >> "$MANIFEST_FILE"
}

collect_system_group() {
  run_capture "system" "uname-a" "$CMD_TIMEOUT" 1 "uname" "uname -a"
  run_capture "system" "hostnamectl" "$CMD_TIMEOUT" 1 "hostnamectl" "hostnamectl"
  run_capture "system" "uptime" "$CMD_TIMEOUT" 1 "uptime" "uptime"
  run_capture "system" "os-release" "$CMD_TIMEOUT" 1 "cat" "cat /etc/os-release"
  run_capture "system" "kernel-cmdline" "$CMD_TIMEOUT" 1 "cat" "cat /proc/cmdline"
  run_capture "system" "timedatectl" "$CMD_TIMEOUT" 0 "timedatectl" "timedatectl"
  run_capture "system" "free-h" "$CMD_TIMEOUT" 1 "free" "free -h"
  run_capture "system" "vmstat" "$CMD_TIMEOUT" 0 "vmstat" "vmstat"
  run_capture "system" "top-batch" "$CMD_TIMEOUT" 0 "top" "top -b -n 1"
}

collect_disk_group() {
  run_capture "disk" "lsblk-f" "$CMD_TIMEOUT" 1 "lsblk" "lsblk -f"
  run_capture "disk" "blkid" "$CMD_TIMEOUT" 1 "blkid" "blkid"
  run_capture "disk" "fdisk-l" "$LONG_TIMEOUT" 1 "fdisk" "fdisk -l"
  run_capture "disk" "df-hT" "$CMD_TIMEOUT" 1 "df" "df -hT"
  run_capture "disk" "df-i" "$CMD_TIMEOUT" 1 "df" "df -i"
  run_capture "disk" "findmnt" "$CMD_TIMEOUT" 1 "findmnt" "findmnt"
  run_capture "disk" "fstab" "$CMD_TIMEOUT" 1 "cat" "cat /etc/fstab"
  run_capture "disk" "dmesg-storage-filtered" "$LONG_TIMEOUT" 1 "dmesg" "dmesg -T | grep -Ei 'error|fail|i/o|io error|ext4|xfs|btrfs|nvme|ata|scsi' || true"
  run_capture "disk" "journal-warning-alert" "$LONG_TIMEOUT" 1 "journalctl" "journalctl -b -p warning..alert -n ${MAX_JOURNAL_LINES}"

  run_capture "disk" "smartctl-scan" "$CMD_TIMEOUT" 1 "smartctl" "smartctl --scan-open"

  if command -v lsblk >/dev/null 2>&1 && command -v smartctl >/dev/null 2>&1; then
    local disk_name
    while IFS= read -r disk_name; do
      [[ -n "$disk_name" ]] || continue
      run_capture "disk" "smartctl-${disk_name}" "$LONG_TIMEOUT" 1 "smartctl" "smartctl -a /dev/${disk_name}"
    done < <(lsblk -dn -o NAME,TYPE | awk '$2 == "disk" { print $1 }')
  fi
}

collect_hardware_group() {
  run_capture "hardware" "lscpu" "$CMD_TIMEOUT" 1 "lscpu" "lscpu"
  run_capture "hardware" "lsmem" "$CMD_TIMEOUT" 0 "lsmem" "lsmem"
  run_capture "hardware" "lspci" "$CMD_TIMEOUT" 0 "lspci" "lspci -nn"
  run_capture "hardware" "lsusb" "$CMD_TIMEOUT" 0 "lsusb" "lsusb"
  run_capture "hardware" "dmidecode" "$LONG_TIMEOUT" 1 "dmidecode" "dmidecode"
  run_capture "hardware" "sensors" "$CMD_TIMEOUT" 0 "sensors" "sensors"
}

collect_network_group() {
  run_capture "network" "ip-addr" "$CMD_TIMEOUT" 1 "ip" "ip addr"
  run_capture "network" "ip-link" "$CMD_TIMEOUT" 1 "ip" "ip link"
  run_capture "network" "ip-route" "$CMD_TIMEOUT" 1 "ip" "ip route"

  if command -v resolvectl >/dev/null 2>&1; then
    run_capture "network" "resolvectl-status" "$CMD_TIMEOUT" 0 "resolvectl" "resolvectl status"
  else
    run_capture "network" "resolv-conf" "$CMD_TIMEOUT" 0 "cat" "cat /etc/resolv.conf"
  fi

  run_capture "network" "ss-tulpen" "$CMD_TIMEOUT" 0 "ss" "ss -tulpen"

  if command -v nft >/dev/null 2>&1; then
    run_capture "network" "nft-ruleset" "$CMD_TIMEOUT" 0 "nft" "nft list ruleset"
  elif command -v iptables >/dev/null 2>&1; then
    run_capture "network" "iptables-S" "$CMD_TIMEOUT" 0 "iptables" "iptables -S"
  else
    run_capture "network" "firewall-unavailable" "$CMD_TIMEOUT" 0 "echo" "echo 'Neither nft nor iptables is available.'"
  fi

  run_capture "network" "networkctl" "$CMD_TIMEOUT" 0 "networkctl" "networkctl"
  run_capture "network" "nmcli" "$CMD_TIMEOUT" 0 "nmcli" "nmcli device status"
}

collect_services_group() {
  run_capture "services" "running-services" "$CMD_TIMEOUT" 1 "systemctl" "systemctl list-units --type=service --state=running --no-pager"
  run_capture "services" "failed-services" "$CMD_TIMEOUT" 1 "systemctl" "systemctl list-units --type=service --state=failed --no-pager"
  run_capture "services" "activating-services" "$CMD_TIMEOUT" 1 "systemctl" "systemctl list-units --type=service --state=activating --no-pager"
  run_capture "services" "systemd-failed-summary" "$CMD_TIMEOUT" 1 "systemctl" "systemctl --failed --no-pager"
  run_capture "services" "system-running-state" "$CMD_TIMEOUT" 1 "systemctl" "systemctl is-system-running"
  run_capture "services" "systemd-analyze-blame" "$LONG_TIMEOUT" 0 "systemd-analyze" "systemd-analyze blame"
  run_capture "services" "systemd-analyze-critical-chain" "$LONG_TIMEOUT" 0 "systemd-analyze" "systemd-analyze critical-chain"
}

collect_logs_group() {
  run_capture "logs" "journal-current-boot" "$LONG_TIMEOUT" 1 "journalctl" "journalctl -b -n ${MAX_JOURNAL_LINES}"
  run_capture "logs" "journal-prev-boot" "$LONG_TIMEOUT" 0 "journalctl" "journalctl -b -1 -n ${MAX_JOURNAL_LINES}"
  run_capture "logs" "journal-kernel-current" "$LONG_TIMEOUT" 1 "journalctl" "journalctl -k -b -n ${MAX_JOURNAL_LINES}"
  run_capture "logs" "journal-error-alert" "$LONG_TIMEOUT" 1 "journalctl" "journalctl -b -p err..alert -n ${MAX_JOURNAL_LINES}"
  run_capture "logs" "dmesg-T" "$LONG_TIMEOUT" 1 "dmesg" "dmesg -T"
}

# ---------------------------------------------------------------------------
# File copy helper — captures raw system files verbatim into configs/
# ---------------------------------------------------------------------------
copy_file_to_configs() {
  local src="$1"
  [[ -f "$src" ]] || return 0
  local dest_name
  dest_name="$(printf '%s' "$src" | sed 's|^/||; s|/|_|g')"
  local dest="$CONFIGS_DIR/$dest_name"
  cp "$src" "$dest" 2>/dev/null || return 0
  redact_file "$dest"
  truncate_if_needed "$dest"
  printf 'COPIED_FILE|src=%s|dest=%s\n' "$src" "$dest" >> "$MANIFEST_FILE"
}

# Capture last N lines of a log file into configs/
copy_log_tail_to_configs() {
  local src="$1"
  local lines="${2:-2000}"
  [[ -f "$src" ]] || return 0
  local dest_name
  dest_name="$(printf '%s' "$src" | sed 's|^/||; s|/|_|g')"
  local dest="$CONFIGS_DIR/$dest_name"
  tail -n "$lines" "$src" > "$dest" 2>/dev/null || return 0
  redact_file "$dest"
  truncate_if_needed "$dest"
  printf 'COPIED_FILE|src=%s (last %s lines)|dest=%s\n' "$src" "$lines" "$dest" >> "$MANIFEST_FILE"
}

collect_config_files_group() {
  # Core system config
  copy_file_to_configs "/etc/fstab"
  copy_file_to_configs "/etc/hostname"
  copy_file_to_configs "/etc/hosts"
  copy_file_to_configs "/etc/resolv.conf"
  copy_file_to_configs "/etc/default/grub"
  copy_file_to_configs "/boot/grub/grub.cfg"

  # Network config
  copy_file_to_configs "/etc/network/interfaces"
  local np_file
  for np_file in /etc/netplan/*.yaml /etc/netplan/*.yml; do
    copy_file_to_configs "$np_file"
  done

  # systemd unit files for failed services
  if [[ -f "$RUN_DIR/services/failed-services.txt" ]]; then
    local unit_name
    while IFS= read -r unit_name; do
      [[ -n "$unit_name" ]] || continue
      [[ "$unit_name" == *.service ]] || continue
      copy_file_to_configs "/etc/systemd/system/$unit_name"
      copy_file_to_configs "/usr/lib/systemd/system/$unit_name"
    done < <(awk '/\.service/ { for (i=1; i<=NF; i++) { if ($i ~ /^[[:alnum:]_.@:-]+\.service$/) { print $i; break } } }' "$RUN_DIR/services/failed-services.txt" 2>/dev/null || true)
  fi

  # Traditional log files (tail to keep manageable)
  copy_log_tail_to_configs "/var/log/syslog" 3000
  copy_log_tail_to_configs "/var/log/kern.log" 2000
  copy_log_tail_to_configs "/var/log/boot.log" 1000
  copy_log_tail_to_configs "/var/log/apt/history.log" 500
}

# ---------------------------------------------------------------------------
# Copilot bundle — single consolidated file for LLM analysis
# ---------------------------------------------------------------------------
bundle_section() {
  local title="$1"
  local file="$2"
  local max_lines="${3:-300}"
  local total

  printf '\n================================================================\n' >> "$COPILOT_BUNDLE_FILE"
  printf '%s\n' "$title" >> "$COPILOT_BUNDLE_FILE"
  printf '================================================================\n' >> "$COPILOT_BUNDLE_FILE"

  if [[ -f "$file" && -s "$file" ]]; then
    head -n "$max_lines" "$file" >> "$COPILOT_BUNDLE_FILE"
    total="$(wc -l < "$file" 2>/dev/null || echo 0)"
    if [[ "$total" -gt "$max_lines" ]]; then
      printf '... [TRUNCATED: %s total lines, showing first %s]\n' "$total" "$max_lines" >> "$COPILOT_BUNDLE_FILE"
    fi
  else
    printf '(no data)\n' >> "$COPILOT_BUNDLE_FILE"
  fi
}

build_copilot_bundle() {
  : > "$COPILOT_BUNDLE_FILE"

  {
    printf '================================================================\n'
    printf 'WATCHDOG DIAGNOSTIC BUNDLE\n'
    printf 'Host: %s  |  Generated: %s\n' "$HOSTNAME_VALUE" "$(date -Is)"
    printf '================================================================\n'
    printf '\nHOW TO USE:\n'
    printf 'Upload or paste this file into a GitHub Copilot conversation.\n'
    printf 'Ask: "Analyze this diagnostic bundle and identify root causes\n'
    printf 'and remediation steps for any issues found."\n'
    printf 'Sections are ordered from most actionable to supporting context.\n'
  } >> "$COPILOT_BUNDLE_FILE"

  # --- Tier 1: most actionable ---
  bundle_section "[1] RUN INFO" "$RUN_INFO_FILE" 30
  bundle_section "[2] CRITICAL FINDINGS (disk/boot errors)" "$RUN_DIR/meta/critical-findings.txt" 200
  bundle_section "[3] FAILED SERVICES" "$RUN_DIR/services/failed-services.txt" 100
  bundle_section "[4] SYSTEMD FAILED SUMMARY" "$RUN_DIR/services/systemd-failed-summary.txt" 80
  bundle_section "[5] SYSTEM RUNNING STATE" "$RUN_DIR/services/system-running-state.txt" 10

  # --- Tier 2: disk health ---
  bundle_section "[6] BLOCK DEVICES" "$RUN_DIR/disk/lsblk-f.txt" 80
  bundle_section "[7] FILESYSTEM USAGE (df -hT)" "$RUN_DIR/disk/df-hT.txt" 50
  bundle_section "[8] INODE USAGE (df -i)" "$RUN_DIR/disk/df-i.txt" 50
  bundle_section "[9] MOUNT POINTS" "$RUN_DIR/disk/findmnt.txt" 80
  bundle_section "[10] FSTAB" "$RUN_DIR/disk/fstab.txt" 50
  bundle_section "[11] DISK ERRORS (dmesg filtered)" "$RUN_DIR/disk/dmesg-storage-filtered.txt" 200
  bundle_section "[12] JOURNAL WARNINGS AND ALERTS" "$RUN_DIR/disk/journal-warning-alert.txt" 200

  local sf
  local sf_idx=13
  for sf in "$RUN_DIR/disk"/smartctl-*.txt; do
    [[ -f "$sf" ]] || continue
    [[ "$sf" == *smartctl-scan* ]] && continue
    bundle_section "[$sf_idx] SMART: ${sf##*/}" "$sf" 80
    sf_idx=$((sf_idx + 1))
  done

  # --- Tier 3: system baseline ---
  bundle_section "[$sf_idx] KERNEL AND OS" "$RUN_DIR/system/uname-a.txt" 5; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] OS RELEASE" "$RUN_DIR/system/os-release.txt" 20; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] KERNEL CMDLINE" "$RUN_DIR/system/kernel-cmdline.txt" 5; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] UPTIME" "$RUN_DIR/system/uptime.txt" 5; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] MEMORY" "$RUN_DIR/system/free-h.txt" 10; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] CLOCK AND TIME SYNC" "$RUN_DIR/system/timedatectl.txt" 20; sf_idx=$((sf_idx+1))

  # --- Tier 4: startup performance ---
  bundle_section "[$sf_idx] STARTUP BLAME" "$RUN_DIR/services/systemd-analyze-blame.txt" 50; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] STARTUP CRITICAL CHAIN" "$RUN_DIR/services/systemd-analyze-critical-chain.txt" 50; sf_idx=$((sf_idx+1))

  # --- Tier 5: key config files (raw copies) ---
  bundle_section "[$sf_idx] GRUB DEFAULTS" "$CONFIGS_DIR/etc_default_grub" 50; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] FSTAB (raw)" "$CONFIGS_DIR/etc_fstab" 50; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] NETWORK INTERFACES" "$CONFIGS_DIR/etc_network_interfaces" 50; sf_idx=$((sf_idx+1))

  local np
  for np in "$CONFIGS_DIR"/etc_netplan_*; do
    [[ -f "$np" ]] || continue
    bundle_section "[$sf_idx] NETPLAN: ${np##*/}" "$np" 80
    sf_idx=$((sf_idx+1))
  done

  local failed_unit
  for failed_unit in "$CONFIGS_DIR"/*.service; do
    [[ -f "$failed_unit" ]] || continue
    bundle_section "[$sf_idx] FAILED UNIT FILE: ${failed_unit##*/}" "$failed_unit" 60
    sf_idx=$((sf_idx+1))
  done

  # --- Tier 6: journal errors and logs ---
  bundle_section "[$sf_idx] JOURNAL ERRORS (current boot)" "$RUN_DIR/logs/journal-error-alert.txt" 300; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] KERNEL RING BUFFER (dmesg)" "$RUN_DIR/logs/dmesg-T.txt" 300; sf_idx=$((sf_idx+1))

  local logname
  for logname in syslog kern.log boot.log; do
    local lf="$CONFIGS_DIR/var_log_${logname}"
    [[ -f "$lf" ]] && { bundle_section "[$sf_idx] LOG: $logname" "$lf" 300; sf_idx=$((sf_idx+1)); }
  done

  # --- Tier 7: supporting context ---
  bundle_section "[$sf_idx] NETWORK INTERFACES (ip addr)" "$RUN_DIR/network/ip-addr.txt" 60; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] ROUTES" "$RUN_DIR/network/ip-route.txt" 30; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] LISTENING PORTS" "$RUN_DIR/network/ss-tulpen.txt" 80; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] CPU" "$RUN_DIR/hardware/lscpu.txt" 40; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] RUNNING SERVICES" "$RUN_DIR/services/running-services.txt" 100; sf_idx=$((sf_idx+1))
  bundle_section "[$sf_idx] ACTIVATING SERVICES" "$RUN_DIR/services/activating-services.txt" 30; sf_idx=$((sf_idx+1))

  {
    printf '\n================================================================\n'
    printf 'COLLECTED FILE COPIES (configs/ directory listing)\n'
    printf '================================================================\n'
    ls -lh "$CONFIGS_DIR/" 2>/dev/null || printf '(none)\n'
    printf '\n================================================================\n'
    printf 'END OF BUNDLE\n'
    printf '================================================================\n'
  } >> "$COPILOT_BUNDLE_FILE"
}

count_services() {
  local file="$1"
  if [[ -f "$file" ]]; then
    awk '/\.service/ { for (i=1; i<=NF; i++) { if ($i ~ /^[[:alnum:]_.@:-]+\.service$/) { print $i; break } } }' "$file" | wc -l
  else
    echo 0
  fi
}

build_summary() {
  local running_count failed_count activating_count
  local critical_file="$RUN_DIR/meta/critical-findings.txt"

  running_count="$(count_services "$RUN_DIR/services/running-services.txt")"
  failed_count="$(count_services "$RUN_DIR/services/failed-services.txt")"
  activating_count="$(count_services "$RUN_DIR/services/activating-services.txt")"

  : > "$critical_file"

  {
    grep -Ei 'i/o error|io error|buffer i/o|blk_update_request|critical medium error|read-only file system|remounting filesystem read-only' "$RUN_DIR/logs/dmesg-T.txt" 2>/dev/null || true
    grep -Ei 'i/o error|mount.*failed|read-only file system|remount' "$RUN_DIR/logs/journal-error-alert.txt" 2>/dev/null || true
    grep -Ei 'SMART overall-health self-assessment test result: FAILED|SMART Health Status: BAD|SMART.*FAILED' "$RUN_DIR/disk"/smartctl-*.txt 2>/dev/null || true
  } > "$critical_file"

  {
    echo "WATCHDOG Offline Diagnostics Summary"
    echo "Generated: $(date -Is)"
    echo "Host: $HOSTNAME_VALUE"
    echo "Output root: $OUTPUT_ROOT"
    echo "Run directory: $RUN_DIR"
    echo "Archive path: $ARCHIVE_PATH"
    echo ""
    echo "Service Health"
    echo "- Running services: $running_count"
    echo "- Failed services: $failed_count"
    echo "- Activating services: $activating_count"
    echo ""
    echo "Collection Health"
    echo "- Mandatory failures: $MANDATORY_FAILURES"
    echo "- Total errors: $TOTAL_ERRORS"
    echo "- Truncated files: $TRUNCATION_COUNT"
    echo ""
    echo "Critical Findings"
    if [[ -s "$critical_file" ]]; then
      sed 's/^/- /' "$critical_file"
    else
      echo "- No critical disk/boot signatures detected by pattern scan"
    fi
    echo ""
    echo "Notes"
    echo "- Check errors.txt for failed commands and stderr paths."
    echo "- Check manifest.txt for full command execution trace."
  } > "$SUMMARY_FILE"
}

write_run_info() {
  local end_epoch end_iso duration
  end_epoch="$(date +%s)"
  end_iso="$(date -Is)"
  duration="$((end_epoch - START_EPOCH))"

  {
    echo "script_name=$SCRIPT_NAME"
    echo "script_version=$SCRIPT_VERSION"
    echo "host=$HOSTNAME_VALUE"
    echo "kernel=$(uname -r 2>/dev/null || echo unknown)"
    echo "start_time=$START_ISO"
    echo "end_time=$end_iso"
    echo "duration_seconds=$duration"
    echo "output_root=$OUTPUT_ROOT"
    echo "run_dir=$RUN_DIR"
    echo "archive_path=$ARCHIVE_PATH"
  } > "$RUN_INFO_FILE"
}

create_archive() {
  local host_root archive_file
  host_root="$OUTPUT_ROOT/diagnostics/$HOSTNAME_VALUE"
  archive_file="$host_root/${TIMESTAMP_VALUE}.tar.gz"
  ARCHIVE_PATH="$archive_file"

  tar -czf "$archive_file" -C "$host_root" "$TIMESTAMP_VALUE" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  return 0
}

main() {
  local final_exit=0

  parse_args "$@"
  ensure_root
  resolve_output_root
  ensure_output_tree

  log "Collecting diagnostics into: $RUN_DIR"

  collect_system_group
  collect_disk_group
  collect_hardware_group
  collect_network_group
  collect_services_group
  collect_logs_group
  collect_config_files_group

  if [[ "$MANDATORY_FAILURES" -gt 0 ]]; then
    final_exit=1
  else
    final_exit=0
  fi

  if ! create_archive; then
    ARCHIVE_PATH=""
    final_exit=3
  fi

  printf '%s\n' "$final_exit" > "$EXIT_CODE_FILE"
  build_summary
  write_run_info
  build_copilot_bundle

  log "Summary:       $SUMMARY_FILE"
  log "Copilot bundle: $COPILOT_BUNDLE_FILE"
  log "Manifest:      $MANIFEST_FILE"
  log "Errors:        $ERRORS_FILE"
  log "Config files:  $CONFIGS_DIR"
  if [[ -n "$ARCHIVE_PATH" ]]; then
    log "Archive:       $ARCHIVE_PATH"
  else
    log_err "Archive creation failed."
  fi

  exit "$final_exit"
}

main "$@"
