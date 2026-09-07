#!/bin/bash
set -e

# One-time setup so the privacy bar plugin can toggle the webcam without root.
# Installs a udev rule that grants a group ("wheel" by default) write access to
# the USB device's "authorized" sysfs attribute, then fixes up the device that
# is currently plugged in. Also installs a restore-on-(re)enumeration systemd
# service, because the kernel always resets "authorized" to 1 (enabled)
# whenever the device is added — at boot, on resume, or on replug — with no
# memory of what was set before shutdown. Without this, the webcam toggle
# would silently reset to "on" every reboot.
#
# The webcam is auto-detected (first USB device with a UVC video interface).
# Override by setting WEBCAM_USB_ID=VID:PID — either in the environment or in
# ~/.config/privacy-bar/webcam.conf. WEBCAM_GROUP overrides the "wheel" group.

RULE_FILE="/etc/udev/rules.d/99-webcam-toggle.rules"
STATE_DIR="/var/lib/privacy-bar"
STATE_FILE="$STATE_DIR/webcam-state"
SERVICE_FILE="/etc/systemd/system/privacy-webcam-restore.service"
GROUP="${WEBCAM_GROUP:-wheel}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESTORE_SCRIPT="$SCRIPT_DIR/webcam-restore.sh"
. "$SCRIPT_DIR/webcam-lib.sh"

# Resolve the webcam's USB id (honours WEBCAM_USB_ID, else auto-detects).
USB_ID="$(webcam_usb_id || true)"
if [ -z "$USB_ID" ]; then
  echo "ERROR: no USB webcam found." >&2
  echo "Plug the camera in and re-run, or set WEBCAM_USB_ID=VID:PID (e.g. in" >&2
  echo "~/.config/privacy-bar/webcam.conf) and re-run." >&2
  exit 1
fi
VENDOR_ID="${USB_ID%%:*}"
PRODUCT_ID="${USB_ID##*:}"
ID_FILE="$STATE_DIR/webcam-usb-id"
echo "Webcam: USB $VENDOR_ID:$PRODUCT_ID  (group: $GROUP)"

if ! getent group "$GROUP" >/dev/null; then
  echo "ERROR: group '$GROUP' does not exist." >&2
  exit 1
fi

echo "Creating persistent state store at $STATE_FILE..."
mkdir -p "$STATE_DIR"

# Persist the resolved USB id so the plugin can still find the camera by
# vendor:product after it has been toggled off (de-authorising a USB device
# tears down its interfaces, so interface-class detection stops working).
printf '%s:%s\n' "$VENDOR_ID" "$PRODUCT_ID" > "$ID_FILE"
chmod a+r "$ID_FILE"
if [ ! -f "$STATE_FILE" ]; then
  # Seed with the device's current authorized value if it's plugged in now,
  # otherwise default to authorized (1 = camera on).
  seed="1"
  dev="$(find_webcam_sysfs || true)"
  [ -n "$dev" ] && [ -f "$dev/authorized" ] && seed="$(cat "$dev/authorized")"
  echo "$seed" > "$STATE_FILE"
fi
chgrp "$GROUP" "$STATE_FILE"
chmod g+w "$STATE_FILE"

echo "Installing restore-on-boot service at $SERVICE_FILE..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Restore privacy-bar webcam authorized state

[Service]
Type=oneshot
Environment=WEBCAM_USB_ID=$VENDOR_ID:$PRODUCT_ID
ExecStart=$RESTORE_SCRIPT
EOF

echo "Creating udev rule at $RULE_FILE..."
cat << EOF > "$RULE_FILE"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", RUN+="/bin/sh -c 'chgrp $GROUP /sys\$devpath/authorized && chmod g+w /sys\$devpath/authorized'", TAG+="systemd", ENV{SYSTEMD_WANTS}+="privacy-webcam-restore.service"
EOF

echo "Reloading systemd units..."
systemctl daemon-reload

echo "Reloading udev rules..."
udevadm control --reload-rules

echo "Triggering udev rules..."
udevadm trigger

# Apply permissions to the device that is already plugged in, so there is no
# need to unplug/replug.
dev="$(find_webcam_sysfs || true)"
if [ -n "$dev" ] && [ -f "$dev/authorized" ]; then
  echo "Applying group permissions to $dev/authorized ..."
  chgrp "$GROUP" "$dev/authorized"
  chmod g+w "$dev/authorized"
fi

echo "Udev configuration complete!"
