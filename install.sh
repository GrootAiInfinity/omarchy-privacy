#!/usr/bin/env bash
# Install AND enable the privacy widget: copies the files, adds the widget to the
# omarchy bar layout, and reloads the shell. Idempotent.
#
# The webcam toggle also needs a one-time root step (udev rule + restore
# service). This script prints that command at the end; the mic toggle works
# without it.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${OMARCHY_CONFIG:-$HOME/.config/omarchy}"
SHELL_JSON="$CFG/shell.json"
ID="privacy"

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

install -Dm644 "$SRC/bar/modules/$ID.qml"            "$CFG/bar/modules/$ID.qml"
install -Dm755 "$SRC/bar/scripts/privacy-control.sh" "$CFG/bar/scripts/privacy-control.sh"
install -Dm755 "$SRC/bar/scripts/setup_udev.sh"      "$CFG/bar/scripts/setup_udev.sh"
install -Dm755 "$SRC/bar/scripts/webcam-restore.sh"  "$CFG/bar/scripts/webcam-restore.sh"
# point the widget/scripts at this machine's $HOME
sed -i "s#/home/groot/#$HOME/#g" "$CFG/bar/modules/$ID.qml" "$CFG/bar/scripts/setup_udev.sh"

cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
tmp="$(mktemp)"
jq --arg id "$ID" '
  ({id:$id, type:"qml"}) as $entry
  | if (.bar.layout | type) == "object"
    then .bar.layout.right = ((.bar.layout.right // [])
         | if any(.[]?; .id == $id) then . else . + [$entry] end)
    else .bar.layout = ((.bar.layout // [])
         | if any(.[]?; .id == $id) then . else . + [$entry] end)
    end
' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"

omarchy restart shell 2>/dev/null || true
echo "privacy widget installed and enabled (mic toggle works now)."
echo "For the webcam toggle, run once:"
echo "  sudo $CFG/bar/scripts/setup_udev.sh"
echo "(first edit the USB id 13d3:56a2 in privacy-control.sh / webcam-restore.sh /"
echo " setup_udev.sh if your camera differs — check 'lsusb')"
