#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/webcam-lib.sh"

# Persisted last-known camera state, so it can be restored after a reboot
# (the kernel always re-authorizes/enables the USB device on enumeration and
# has no memory of what was set before shutdown — see webcam-restore.sh).
# The path comes from webcam-lib.sh, which also resolves the pre-1.1 location.
STATE_FILE="$WEBCAM_STATE_FILE"

# Command the user must run once to grant non-root access to the webcam.
SETUP_CMD="sudo bash '$SCRIPT_DIR/setup_udev.sh'"

# Find the webcam's "authorized" sysfs file (empty if no webcam present).
CAM_FILE=""
CAM_DIR="$(find_webcam_sysfs || true)"
[ -n "$CAM_DIR" ] && [ -f "$CAM_DIR/authorized" ] && CAM_FILE="$CAM_DIR/authorized"

get_status() {
  local mic_muted=false
  if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q "\[MUTED\]"; then
    mic_muted=true
  fi

  local camera_disabled=false
  local camera_present=false
  local camera_writable=false
  if [ -n "$CAM_FILE" ] && [ -f "$CAM_FILE" ]; then
    camera_present=true
    if [ "$(cat "$CAM_FILE" 2>/dev/null)" = "0" ]; then
      camera_disabled=true
    fi
    if [ -w "$CAM_FILE" ]; then
      camera_writable=true
    fi
  fi

  local privacy_active=false
  if [ "$mic_muted" = "true" ] && { [ "$camera_present" = "false" ] || [ "$camera_disabled" = "true" ] || [ "$camera_writable" = "false" ]; }; then
    privacy_active=true
  fi

  cat <<EOF
{
  "mic_muted": $mic_muted,
  "camera_disabled": $camera_disabled,
  "camera_present": $camera_present,
  "camera_writable": $camera_writable,
  "privacy_active": $privacy_active
}
EOF
}

# Write to the camera's authorized file and persist the value so
# webcam-restore.sh can re-apply it after the next boot.
write_cam() {
  local val="$1"
  echo "$val" > "$CAM_FILE"
  if [ -w "$STATE_FILE" ]; then
    echo "$val" > "$STATE_FILE"
  fi
}

set_privacy() {
  local enable="$1"
  
  # 1. Toggle Microphone
  if [ "$enable" = "true" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null
  else
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null
  fi

  # 2. Toggle Camera
  if [ -n "$CAM_FILE" ] && [ -f "$CAM_FILE" ]; then
    if [ -w "$CAM_FILE" ]; then
      if [ "$enable" = "true" ]; then
        write_cam 0
      else
        write_cam 1
      fi
    else
      echo "Error: Camera control file not writable. Please run: $SETUP_CMD" >&2
    fi
  fi
}

case "$1" in
  status)
    get_status
    ;;
  on)
    set_privacy true
    get_status
    ;;
  off)
    set_privacy false
    get_status
    ;;
  toggle)
    # Read status to see what to do
    status_json=$(get_status)
    mic_muted=$(echo "$status_json" | grep '"mic_muted"' | awk '{print $2}' | tr -d ',')
    camera_writable=$(echo "$status_json" | grep '"camera_writable"' | awk '{print $2}' | tr -d ',')
    camera_disabled=$(echo "$status_json" | grep '"camera_disabled"' | awk '{print $2}' | tr -d ',')
    
    if [ "$camera_writable" = "true" ]; then
      if [ "$mic_muted" = "true" ] && [ "$camera_disabled" = "true" ]; then
        set_privacy false
      else
        set_privacy true
      fi
    else
      if [ "$mic_muted" = "true" ]; then
        set_privacy false
      else
        set_privacy true
      fi
    fi
    get_status
    ;;
  mic-on)
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null
    get_status
    ;;
  mic-off)
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null
    get_status
    ;;
  mic-toggle)
    if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q "\[MUTED\]"; then
      wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null
    else
      wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null
    fi
    get_status
    ;;
  cam-on)
    if [ -n "$CAM_FILE" ] && [ -f "$CAM_FILE" ]; then
      if [ -w "$CAM_FILE" ]; then
        write_cam 1
      else
        echo "Error: Camera control file not writable. Please run: $SETUP_CMD" >&2
        exit 1
      fi
    fi
    get_status
    ;;
  cam-off)
    if [ -n "$CAM_FILE" ] && [ -f "$CAM_FILE" ]; then
      if [ -w "$CAM_FILE" ]; then
        write_cam 0
      else
        echo "Error: Camera control file not writable. Please run: $SETUP_CMD" >&2
        exit 1
      fi
    fi
    get_status
    ;;
  cam-toggle)
    if [ -n "$CAM_FILE" ] && [ -f "$CAM_FILE" ]; then
      if [ -w "$CAM_FILE" ]; then
        if [ "$(cat "$CAM_FILE" 2>/dev/null)" = "0" ]; then
          write_cam 1
        else
          write_cam 0
        fi
      else
        echo "Error: Camera control file not writable. Please run: $SETUP_CMD" >&2
        exit 1
      fi
    fi
    get_status
    ;;
  *)
    echo "Usage: $0 {status|on|off|toggle|mic-on|mic-off|mic-toggle|cam-on|cam-off|cam-toggle}" >&2
    exit 1
    ;;
esac
