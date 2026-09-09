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
# Every file it writes carries $MARKER and is named after the plugin. A file
# that already exists without that marker belongs to something else and is
# never overwritten: setup stops and tells you what to look at (override with
# PRIVACY_FORCE=1 once you are sure it is safe).
#
# The webcam is auto-detected (first USB device with a UVC video interface).
# Override by setting WEBCAM_USB_ID=VID:PID — either in the environment or in
# ~/.config/omarchy-privacy/webcam.conf. WEBCAM_GROUP overrides the "wheel" group.

MARKER="# managed by the io.github.grootaiinfinity.privacy plugin"

RULE_FILE="/etc/udev/rules.d/99-omarchy-privacy-webcam.rules"
SERVICE_NAME="omarchy-privacy-webcam-restore.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# Everything root executes lives here, root-owned and writable by nobody else.
# The plugin checkout is inside the user's home, so a service or udev rule
# pointing at it would let anyone who can write that directory run code as root
# at the next boot or camera replug. The checkout is the *source*; this is what
# actually gets run.
LIBDIR="/usr/local/lib/omarchy-privacy"

# Pre-1.1 locations. Generic enough to collide with something else on the
# system, which is why they were renamed; migrated below when they are ours.
LEGACY_RULE_FILE="/etc/udev/rules.d/99-webcam-toggle.rules"
LEGACY_SERVICE_NAME="privacy-webcam-restore.service"
LEGACY_SERVICE_FILE="/etc/systemd/system/$LEGACY_SERVICE_NAME"
LEGACY_STATE_DIR="/var/lib/privacy-bar"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESTORE_SCRIPT="$LIBDIR/webcam-restore.sh"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "ERROR: must run as root (use sudo)." >&2
  exit 1
fi

# --- migrate off the pre-1.1 file names -------------------------------------
# Only touched when the content is recognisably this plugin's, so a same-named
# file belonging to anything else is left exactly where it is.
if [ -f "$LEGACY_RULE_FILE" ] && grep -q "$LEGACY_SERVICE_NAME" "$LEGACY_RULE_FILE" 2>/dev/null; then
  echo "Removing the pre-1.1 udev rule at $LEGACY_RULE_FILE ..."
  rm -f "$LEGACY_RULE_FILE"
fi
if [ -f "$LEGACY_SERVICE_FILE" ] && grep -q "webcam-restore.sh" "$LEGACY_SERVICE_FILE" 2>/dev/null; then
  echo "Removing the pre-1.1 restore service at $LEGACY_SERVICE_FILE ..."
  systemctl disable --now "$LEGACY_SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$LEGACY_SERVICE_FILE"
fi

# Pull the saved camera state across before webcam-lib.sh resolves the store,
# so a camera that is currently switched off stays off through the rename.
STATE_DIR="/var/lib/omarchy-privacy"
if [ -d "$LEGACY_STATE_DIR" ] && [ ! -d "$STATE_DIR" ]; then
  echo "Moving the saved state from $LEGACY_STATE_DIR to $STATE_DIR ..."
  mv "$LEGACY_STATE_DIR" "$STATE_DIR"
fi

WEBCAM_STATE_DIR="$STATE_DIR"
export WEBCAM_STATE_DIR
# The library refuses to read a user-writable config when it is loaded by root
# non-interactively. Setup is different: an admin ran it on purpose and the
# documented way to pin a camera is ~/.config/omarchy-privacy/webcam.conf, so
# opt in explicitly. The value is parsed as a literal VID:PID, never executed.
export WEBCAM_ALLOW_USER_CONF=1
. "$SCRIPT_DIR/webcam-lib.sh"

# Resolve the group only after the config has been read. This used to be set
# before the library was loaded, so WEBCAM_GROUP in webcam.conf was silently
# ignored and only the environment variable ever took effect, despite both
# being documented.
_webcam_load_conf
GROUP="${WEBCAM_GROUP:-wheel}"

STATE_FILE="$WEBCAM_STATE_FILE"
ID_FILE="$WEBCAM_ID_FILE"

# --- refuse to clobber a file this plugin did not write ----------------------
guard_write() {
  local f="$1"
  [ -e "$f" ] || return 0
  grep -qF "$MARKER" "$f" 2>/dev/null && return 0
  echo "ERROR: $f already exists and was not created by this plugin." >&2
  echo "       Refusing to overwrite it — inspect it, move it aside, and re-run." >&2
  echo "       Re-run with PRIVACY_FORCE=1 to overwrite it anyway." >&2
  [ "${PRIVACY_FORCE:-0}" = "1" ] || exit 1
  echo "WARNING: PRIVACY_FORCE=1 — overwriting $f" >&2
}

guard_write "$RULE_FILE"
guard_write "$SERVICE_FILE"

# Resolve the webcam's USB id (honours WEBCAM_USB_ID, else auto-detects).
USB_ID="$(webcam_usb_id || true)"
if [ -z "$USB_ID" ]; then
  echo "ERROR: no USB webcam found." >&2
  echo "Plug the camera in and re-run, or set WEBCAM_USB_ID=VID:PID (e.g. in" >&2
  echo "~/.config/omarchy-privacy/webcam.conf) and re-run." >&2
  exit 1
fi
VENDOR_ID="${USB_ID%%:*}"
PRODUCT_ID="${USB_ID##*:}"
echo "Webcam: USB $VENDOR_ID:$PRODUCT_ID  (group: $GROUP)"

if ! getent group "$GROUP" >/dev/null; then
  echo "ERROR: group '$GROUP' does not exist." >&2
  exit 1
fi

# Every member of $GROUP can switch the camera on and off from here on — say so
# out loud rather than only in the README, since this is the one durable
# permission change the setup makes.
echo "Note: this grants every member of the '$GROUP' group write access to the"
echo "      camera's USB 'authorized' attribute (power on/off), not just you."

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

echo "Installing root-executed helpers at $LIBDIR ..."
install -d -m 0755 -o root -g root "$LIBDIR"
install -m 0755 -o root -g root "$SCRIPT_DIR/webcam-restore.sh" "$LIBDIR/webcam-restore.sh"
install -m 0644 -o root -g root "$SCRIPT_DIR/webcam-lib.sh"     "$LIBDIR/webcam-lib.sh"

# Verify rather than assume: if these are not root-owned and unwritable by
# anyone else, the service below must not be created pointing at them.
for f in "$LIBDIR" "$LIBDIR/webcam-restore.sh" "$LIBDIR/webcam-lib.sh"; do
  if [ "$(stat -c '%u' "$f")" != "0" ] || [ -n "$(find "$f" -maxdepth 0 -perm /022 -print)" ]; then
    echo "ERROR: $f is not root-owned or is writable by others — refusing to continue." >&2
    exit 1
  fi
done

echo "Installing restore-on-boot service at $SERVICE_FILE..."
cat << EOF > "$SERVICE_FILE"
$MARKER
[Unit]
Description=Restore omarchy-privacy webcam authorized state

[Service]
Type=oneshot
Environment=WEBCAM_USB_ID=$VENDOR_ID:$PRODUCT_ID
ExecStart=$RESTORE_SCRIPT
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectControlGroups=yes
ProtectKernelLogs=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
EOF

echo "Creating udev rule at $RULE_FILE..."
cat << EOF > "$RULE_FILE"
$MARKER
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", RUN+="/bin/sh -c 'chgrp $GROUP /sys\$devpath/authorized && chmod g+w /sys\$devpath/authorized'", TAG+="systemd", ENV{SYSTEMD_WANTS}+="$SERVICE_NAME"
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
