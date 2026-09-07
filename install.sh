#!/usr/bin/env bash
# Install the privacy bar widget into ~/.config/omarchy.
# Run  sudo ./bar/scripts/setup_udev.sh  afterwards for the one-time root setup.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${OMARCHY_CONFIG:-$HOME/.config/omarchy}"

install -Dm644 "$SRC/bar/modules/privacy.qml"       "$DEST/bar/modules/privacy.qml"
install -Dm755 "$SRC/bar/scripts/privacy-control.sh" "$DEST/bar/scripts/privacy-control.sh"
install -Dm755 "$SRC/bar/scripts/setup_udev.sh"      "$DEST/bar/scripts/setup_udev.sh"
install -Dm755 "$SRC/bar/scripts/webcam-restore.sh"  "$DEST/bar/scripts/webcam-restore.sh"

echo "Installed the privacy widget and scripts into $DEST"
echo
echo "Next:"
echo "  1. sudo $DEST/bar/scripts/setup_udev.sh    # one-time root setup"
echo "  2. add  { \"id\": \"privacy\", \"type\": \"qml\" }  to bar.layout in $DEST/shell.json"
echo "  3. omarchy restart shell"

if [ "$USER" != "groot" ]; then
  echo
  echo "NOTE: username is '$USER', not 'groot'. Edit the hard-coded /home/groot"
  echo "paths in privacy.qml and bar/scripts/setup_udev.sh, and the USB id"
  echo "(13d3:56a2) in privacy-control.sh / webcam-restore.sh / setup_udev.sh."
fi
