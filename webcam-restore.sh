#!/bin/bash
# Run by udev (via systemd) whenever the webcam USB device is (re-)added —
# on boot, resume, or replug. The kernel always resets the device's
# "authorized" sysfs attribute to 1 (enabled) on enumeration; it has no
# memory of what the privacy bar plugin last set it to. This script re-applies
# the last saved state so the toggle survives a reboot/shutdown.
#
# setup_udev.sh bakes WEBCAM_USB_ID into this service's environment so the
# lookup is deterministic even when run from the early-boot udev context.
#
# This runs as root. setup_udev.sh therefore installs a root-owned copy of this
# script and of webcam-lib.sh under /usr/local/lib/omarchy-privacy and points
# the unit at that copy — never at the plugin checkout, which lives in the
# user's home and which the user can rewrite at any time. The check below
# enforces the same rule at run time, so a unit pointed somewhere writable
# fails loudly instead of executing whatever it finds there.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/webcam-lib.sh"

# Root-owned and writable by nobody else — checked for the file itself and for
# every directory above it, since a writable parent is just as good as a
# writable file to anyone swapping it out.
_trusted_path() {
  local p="$1"
  while :; do
    [ "$(stat -c '%u' "$p" 2>/dev/null)" = "0" ] || return 1
    [ -z "$(find "$p" -maxdepth 0 -perm /022 -print 2>/dev/null)" ] || return 1
    [ "$p" = "/" ] && return 0
    p="$(dirname "$p")"
  done
}

if [ "$(id -u)" -eq 0 ]; then
  for path in "$0" "$LIB"; do
    _trusted_path "$path" || {
      echo "webcam-restore: refusing to run as root — $path is not root-owned," \
           "or it (or a directory above it) is writable by others." >&2
      exit 1
    }
  done
fi

. "$LIB"

STATE_FILE="$WEBCAM_STATE_FILE"

dev="$(find_webcam_sysfs)" || exit 0
[ -f "$dev/authorized" ] || exit 0

state="1"
if [ -f "$STATE_FILE" ]; then
  saved="$(cat "$STATE_FILE" 2>/dev/null)"
  case "$saved" in
    0|1) state="$saved" ;;
  esac
fi
echo "$state" > "$dev/authorized"
