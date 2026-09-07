#!/bin/bash
# Run by udev (via systemd) whenever the webcam USB device is (re-)added —
# on boot, resume, or replug. The kernel always resets the device's
# "authorized" sysfs attribute to 1 (enabled) on enumeration; it has no
# memory of what the privacy bar plugin last set it to. This script re-applies
# the last saved state so the toggle survives a reboot/shutdown.
#
# setup_udev.sh bakes WEBCAM_USB_ID into this service's environment so the
# lookup is deterministic even when run from the early-boot udev context.

STATE_FILE="/var/lib/privacy-bar/webcam-state"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/webcam-lib.sh"

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
