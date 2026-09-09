#!/bin/bash
# Undo setup_udev.sh — remove the system-side state the privacy bar plugin
# installs for the webcam toggle.
#
# Run as root:  sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/uninstall_udev.sh
#
# Removes the udev rule, the restore-on-enumeration service and the persistent
# state directory. The camera is re-authorised first: once the state file and
# the restore service are gone nothing would ever set "authorized" back to 1,
# so a camera that happened to be toggled off would stay off with no non-root
# way to switch it back on.
#
# The mic toggle needs none of this and keeps working after an uninstall.

set -e

RULE_FILE="/etc/udev/rules.d/99-webcam-toggle.rules"
STATE_DIR="/var/lib/privacy-bar"
SERVICE_FILE="/etc/systemd/system/privacy-webcam-restore.service"
SERVICE_NAME="privacy-webcam-restore.service"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "ERROR: must run as root (use sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/webcam-lib.sh"

# Re-enable the camera while the persisted USB id is still on disk — after
# $STATE_DIR is gone, a de-authorised device can no longer be looked up by
# interface class.
dev="$(find_webcam_sysfs || true)"
if [ -n "$dev" ] && [ -f "$dev/authorized" ]; then
  if [ "$(cat "$dev/authorized" 2>/dev/null)" != "1" ]; then
    echo "Re-authorising the webcam at $dev ..."
  fi
  echo 1 > "$dev/authorized" || true
fi

echo "Removing restore service $SERVICE_FILE ..."
systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
rm -f "$SERVICE_FILE"

echo "Removing udev rule $RULE_FILE ..."
rm -f "$RULE_FILE"

echo "Removing state store $STATE_DIR ..."
rm -rf "$STATE_DIR"

echo "Reloading systemd units..."
systemctl daemon-reload

echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo
echo "Udev configuration removed."
echo "The webcam is back under the kernel default (authorized, group-writable"
echo "permissions dropped on the next re-enumeration)."
echo "Your own config at ~/.config/privacy-bar/webcam.conf was left in place."
echo "Remove the plugin itself with: omarchy plugin remove io.github.grootaiinfinity.privacy"
