#!/bin/bash
set -e

# One-time setup so the privacy bar plugin can toggle the webcam without root.
# Installs a udev rule that grants the "wheel" group write access to the USB
# device's "authorized" sysfs attribute, then fixes up the device that is
# currently plugged in. Also installs a restore-on-(re)enumeration systemd
# service, because the kernel always resets "authorized" to 1 (enabled)
# whenever the device is added — at boot, on resume, or on replug — with no
# memory of what was set before shutdown. Without this, the webcam toggle
# would silently reset to "on" every reboot.

VENDOR_ID="13d3"
PRODUCT_ID="56a2"
RULE_FILE="/etc/udev/rules.d/99-webcam-toggle.rules"
STATE_DIR="/var/lib/privacy-bar"
STATE_FILE="$STATE_DIR/webcam-state"
RESTORE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/webcam-restore.sh"
SERVICE_FILE="/etc/systemd/system/privacy-webcam-restore.service"

echo "Creating persistent state store at $STATE_FILE..."
mkdir -p "$STATE_DIR"
if [ ! -f "$STATE_FILE" ]; then
  # Seed with the device's current authorized value if it's plugged in now,
  # otherwise default to authorized (1 = camera on).
  seed="1"
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
    if [ "$(cat "$dev/idVendor")" = "$VENDOR_ID" ] && [ "$(cat "$dev/idProduct")" = "$PRODUCT_ID" ] && [ -f "$dev/authorized" ]; then
      seed="$(cat "$dev/authorized")"
    fi
  done
  echo "$seed" > "$STATE_FILE"
fi
chgrp wheel "$STATE_FILE"
chmod g+w "$STATE_FILE"

echo "Installing restore-on-boot service at $SERVICE_FILE..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Restore privacy-bar webcam authorized state

[Service]
Type=oneshot
ExecStart=$RESTORE_SCRIPT
EOF

echo "Creating udev rule at $RULE_FILE..."
cat << EOF > "$RULE_FILE"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", RUN+="/bin/sh -c 'chgrp wheel /sys\$devpath/authorized && chmod g+w /sys\$devpath/authorized'", TAG+="systemd", ENV{SYSTEMD_WANTS}+="privacy-webcam-restore.service"
EOF

echo "Reloading systemd units..."
systemctl daemon-reload

echo "Reloading udev rules..."
udevadm control --reload-rules

echo "Triggering udev rules..."
udevadm trigger

# Apply permissions to the device that is already plugged in, so there is no
# need to unplug/replug. Locate it by vendor:product rather than assuming a
# fixed USB bus path.
for dev in /sys/bus/usb/devices/*; do
  [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
  if [ "$(cat "$dev/idVendor")" = "$VENDOR_ID" ] && [ "$(cat "$dev/idProduct")" = "$PRODUCT_ID" ]; then
    if [ -f "$dev/authorized" ]; then
      echo "Applying group permissions to $dev/authorized ..."
      chgrp wheel "$dev/authorized"
      chmod g+w "$dev/authorized"
    fi
  fi
done

echo "Udev configuration complete!"
