#!/bin/bash
# Shared helpers for locating the USB webcam on this machine. Sourced by
# privacy-control.sh, webcam-restore.sh and setup_udev.sh.
#
# Detection order:
#   1. $WEBCAM_USB_ID from the environment
#   2. WEBCAM_USB_ID=VID:PID in ${XDG_CONFIG_HOME:-~/.config}/omarchy-privacy/webcam.conf
#      (the pre-1.1 privacy-bar/webcam.conf is still read; both are also
#      checked under $SUDO_USER's home when run via sudo). The file is *parsed*,
#      never sourced, and is only consulted for an unprivileged caller or when a
#      caller opts in explicitly (WEBCAM_ALLOW_USER_CONF=1, which setup_udev.sh
#      sets because the admin runs it deliberately).
#   3. The USB id persisted by setup_udev.sh ($WEBCAM_ID_FILE) — survives the
#      camera being toggled off, when interface-class detection cannot work
#   4. Auto-detect: a USB device exposing a UVC video interface (class 0e)
#   5. Auto-detect: a USB device whose product/manufacturer string looks like
#      a camera (works even while the device is de-authorised)
#
#   find_webcam_sysfs  -> prints the sysfs dir that holds `authorized`/`idVendor`
#   webcam_usb_id      -> prints "VID:PID" for that device
# Both return non-zero and print nothing when no webcam is found.

# System-side state store. The namespaced directory is authoritative; the
# pre-1.1 path is still honoured when an older setup_udev.sh run is in place,
# so updating the plugin without re-running setup cannot lose the saved camera
# state (and silently power the camera back on at the next boot).
WEBCAM_STATE_DIR_DEFAULT="/var/lib/omarchy-privacy"
WEBCAM_STATE_DIR_LEGACY="/var/lib/privacy-bar"
if [ -z "${WEBCAM_STATE_DIR:-}" ]; then
  if [ ! -d "$WEBCAM_STATE_DIR_DEFAULT" ] && [ -d "$WEBCAM_STATE_DIR_LEGACY" ]; then
    WEBCAM_STATE_DIR="$WEBCAM_STATE_DIR_LEGACY"
  else
    WEBCAM_STATE_DIR="$WEBCAM_STATE_DIR_DEFAULT"
  fi
fi
WEBCAM_ID_FILE="${WEBCAM_ID_FILE:-$WEBCAM_STATE_DIR/webcam-usb-id}"
WEBCAM_STATE_FILE="${WEBCAM_STATE_FILE:-$WEBCAM_STATE_DIR/webcam-state}"

# Extract WEBCAM_USB_ID from a config file *without executing it*. The file
# lives in a user's home and is writable by that user, while this same library
# is loaded by code running as root from the restore service — sourcing it would
# turn "pick my camera" into arbitrary code execution as root on the next boot
# or replug. Only a literal VID:PID (4 hex digits each, optionally quoted) is
# accepted; every other line in the file is ignored.
_webcam_conf_id() {
  [ -r "$1" ] || return 1
  sed -n "s/^[[:space:]]*WEBCAM_USB_ID[[:space:]]*=[[:space:]]*['\"]\{0,1\}\([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\)['\"]\{0,1\}[[:space:]]*\$/\1/p" \
    "$1" 2>/dev/null | head -n1 | grep . || return 1
}

# Home directory of $SUDO_USER, from passwd rather than an assumed /home/<name>.
_webcam_sudo_home() {
  [ -n "${SUDO_USER:-}" ] || return 1
  getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 | grep . || return 1
}

_webcam_load_conf() {
  [ -n "${WEBCAM_USB_ID:-}" ] && return 0

  # A non-interactive root caller (the restore service, udev) takes no direction
  # from a user-writable file: it uses the id baked into the unit by
  # setup_udev.sh, or the root-owned id file below, and nothing else.
  if [ "${EUID:-$(id -u)}" -ne 0 ] || [ "${WEBCAM_ALLOW_USER_CONF:-0}" = "1" ]; then
    local c sudo_home found
    sudo_home="$(_webcam_sudo_home || true)"
    for c in \
      "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-privacy/webcam.conf" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/privacy-bar/webcam.conf" \
      ${sudo_home:+"$sudo_home/.config/omarchy-privacy/webcam.conf"} \
      ${sudo_home:+"$sudo_home/.config/privacy-bar/webcam.conf"}; do
      found="$(_webcam_conf_id "$c" || true)"
      [ -n "$found" ] && { WEBCAM_USB_ID="$found"; break; }
    done
  fi

  # Fall back to the id persisted by setup_udev.sh (root-owned, 0644).
  if [ -z "${WEBCAM_USB_ID:-}" ] && [ -r "$WEBCAM_ID_FILE" ]; then
    local saved; saved="$(cat "$WEBCAM_ID_FILE" 2>/dev/null)"
    case "$saved" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) WEBCAM_USB_ID="$saved" ;;
    esac
  fi
  return 0
}

# Print the sysfs dir of the USB device matching VID:PID ($1), or nothing.
_webcam_by_id() {
  local want="$1" vid pid dev
  vid="${want%%:*}"; pid="${want##*:}"
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ] || continue
    if [ "$(cat "$dev/idVendor" 2>/dev/null)" = "$vid" ] &&
       [ "$(cat "$dev/idProduct" 2>/dev/null)" = "$pid" ]; then
      printf '%s\n' "$dev"; return 0
    fi
  done
  return 1
}

find_webcam_sysfs() {
  _webcam_load_conf

  local dev iface cls desc

  # 1-3. Explicit / persisted USB id.
  if [ -n "${WEBCAM_USB_ID:-}" ]; then
    _webcam_by_id "$WEBCAM_USB_ID" && return 0
    return 1
  fi

  # 4. A USB device that currently exposes a UVC video interface.
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/authorized" ] && [ -f "$dev/idVendor" ] || continue
    for iface in "$dev"/*:*/bInterfaceClass; do
      [ -f "$iface" ] || continue
      cls="$(cat "$iface" 2>/dev/null)"
      [ "$cls" = "0e" ] && { printf '%s\n' "$dev"; return 0; }
    done
  done

  # 5. A USB device whose strings look like a camera (works when de-authorised,
  #    i.e. when the interfaces above have been torn down).
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/authorized" ] && [ -f "$dev/idVendor" ] || continue
    desc="$(cat "$dev/product" "$dev/manufacturer" 2>/dev/null)"
    case "$desc" in
      *[Cc]amera*|*[Ww]ebcam*|*UVC*|*[Cc]am\ *) printf '%s\n' "$dev"; return 0 ;;
    esac
  done

  return 1
}

webcam_usb_id() {
  local dev
  dev="$(find_webcam_sysfs)" || return 1
  printf '%s:%s\n' "$(cat "$dev/idVendor" 2>/dev/null)" "$(cat "$dev/idProduct" 2>/dev/null)"
}
