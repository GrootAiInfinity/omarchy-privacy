#!/bin/bash
# Undo setup_udev.sh — remove the system-side state the privacy bar plugin
# installs for the webcam toggle.
#
# Run as root:  sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/uninstall_udev.sh
#
# Removes the udev rule, the restore-on-enumeration service and the persistent
# state directory — only when they carry this plugin's marker, so a same-named
# file belonging to something else is left alone. The camera is re-authorised
# first: once the state file and the restore service are gone nothing would
# ever set "authorized" back to 1, so a camera that happened to be toggled off
# would stay off with no non-root way to switch it back on.
#
# The mic toggle needs none of this and keeps working after an uninstall.

set -e

MARKER="# managed by the io.github.grootaiinfinity.privacy plugin"

RULE_FILE="/etc/udev/rules.d/99-omarchy-privacy-webcam.rules"
SERVICE_NAME="omarchy-privacy-webcam-restore.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
STATE_DIR="/var/lib/omarchy-privacy"

# Pre-1.1 locations, cleaned up too when the content is recognisably ours.
LEGACY_RULE_FILE="/etc/udev/rules.d/99-webcam-toggle.rules"
LEGACY_SERVICE_NAME="privacy-webcam-restore.service"
LEGACY_SERVICE_FILE="/etc/systemd/system/$LEGACY_SERVICE_NAME"
LEGACY_STATE_DIR="/var/lib/privacy-bar"

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

# Remove $1 only if this plugin wrote it ($2 = pattern identifying a pre-1.1
# file, which predates the marker).
remove_ours() {
  local f="$1" legacy_pattern="${2:-}"
  [ -e "$f" ] || return 0
  if grep -qF "$MARKER" "$f" 2>/dev/null; then
    echo "Removing $f ..."
    rm -f "$f"
  elif [ -n "$legacy_pattern" ] && grep -q "$legacy_pattern" "$f" 2>/dev/null; then
    echo "Removing $f (pre-1.1 install) ..."
    rm -f "$f"
  else
    echo "Leaving $f alone — it was not created by this plugin." >&2
  fi
}

systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
remove_ours "$SERVICE_FILE"
remove_ours "$RULE_FILE"

if [ -e "$LEGACY_SERVICE_FILE" ] || [ -e "$LEGACY_RULE_FILE" ]; then
  systemctl disable --now "$LEGACY_SERVICE_NAME" >/dev/null 2>&1 || true
  remove_ours "$LEGACY_SERVICE_FILE" "webcam-restore.sh"
  remove_ours "$LEGACY_RULE_FILE" "$LEGACY_SERVICE_NAME"
fi

for d in "$STATE_DIR" "$LEGACY_STATE_DIR"; do
  [ -d "$d" ] || continue
  echo "Removing state store $d ..."
  rm -rf "$d"
done

echo "Reloading systemd units..."
systemctl daemon-reload

echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo
echo "Udev configuration removed."
echo "The webcam is back under the kernel default (authorized, group-writable"
echo "permissions dropped on the next re-enumeration)."
echo "Your own config at ~/.config/omarchy-privacy/webcam.conf was left in place."
echo "Remove the plugin itself with: omarchy plugin remove io.github.grootaiinfinity.privacy"
