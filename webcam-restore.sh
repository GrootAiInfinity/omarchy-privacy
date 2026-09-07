#!/bin/bash
# Run by udev (via systemd) whenever the webcam USB device is (re-)added —
# on boot, resume, or replug. The kernel always resets the device's
# "authorized" sysfs attribute to 1 (enabled) on enumeration; it has no
# memory of what the privacy bar plugin last set it to. This script re-applies
# the last saved state so the toggle survives a reboot/shutdown.

STATE_FILE="/var/lib/privacy-bar/webcam-state"
VENDOR_ID="13d3"
PRODUCT_ID="56a2"

for dev in /sys/bus/usb/devices/*; do
  [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
  if [ "$(cat "$dev/idVendor" 2>/dev/null)" = "$VENDOR_ID" ] && [ "$(cat "$dev/idProduct" 2>/dev/null)" = "$PRODUCT_ID" ]; then
    [ -f "$dev/authorized" ] || continue
    state="1"
    if [ -f "$STATE_FILE" ]; then
      saved="$(cat "$STATE_FILE" 2>/dev/null)"
      case "$saved" in
        0|1) state="$saved" ;;
      esac
    fi
    echo "$state" > "$dev/authorized"
    exit 0
  fi
done
