#!/bin/bash
# Shared helpers for locating the USB webcam on this machine. Sourced by
# privacy-control.sh, webcam-restore.sh and setup_udev.sh.
#
# Detection order:
#   1. $WEBCAM_USB_ID from the environment
#   2. WEBCAM_USB_ID=VID:PID in ${XDG_CONFIG_HOME:-~/.config}/omarchy-privacy/webcam.conf
#      (the pre-1.1 privacy-bar/webcam.conf is still read; both are also
#      checked under $SUDO_USER's home when run via sudo)
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

_webcam_load_conf() {
  [ -n "${WEBCAM_USB_ID:-}" ] && return 0
  local c
  for c in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-privacy/webcam.conf" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/privacy-bar/webcam.conf" \
    ${SUDO_USER:+"/home/$SUDO_USER/.config/omarchy-privacy/webcam.conf"} \
    ${SUDO_USER:+"/home/$SUDO_USER/.config/privacy-bar/webcam.conf"}; do
    [ -r "$c" ] && { . "$c" 2>/dev/null; break; }
  done
  # Fall back to the id persisted by setup_udev.sh.
  if [ -z "${WEBCAM_USB_ID:-}" ] && [ -r "$WEBCAM_ID_FILE" ]; then
    local saved; saved="$(cat "$WEBCAM_ID_FILE" 2>/dev/null)"
    case "$saved" in
      [0-9a-fA-F]*:[0-9a-fA-F]*) WEBCAM_USB_ID="$saved" ;;
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
