# omarchy-privacy

A privacy-controls widget for the [Omarchy](https://omarchy.org/) status bar
(Quickshell). One click to mute the microphone and cut power to the webcam.

## Features

- Bar icon that reflects live state — mic live, webcam live, both live, or
  fully secure.
- Click opens a panel with two toggles:
  - **Microphone** — `wpctl set-mute @DEFAULT_AUDIO_SOURCE@`
  - **Webcam** — writes `0`/`1` to the USB device's `authorized` sysfs
    attribute, so the camera is physically unpowered (not just software-muted).
- Webcam state persists across reboot/resume/replug via a udev-triggered
  restore script (the kernel re-authorises USB devices on every enumeration).

## Requirements

- Omarchy shell (Quickshell-based bar)
- `wireplumber` (`wpctl`)
- A USB webcam (UVC), and one-time root setup for non-root access to its
  `authorized` attribute (see below)
- `udevadm`, `systemd` (standard on Omarchy/Arch)

## Install

```sh
omarchy plugin add https://github.com/GrootAiInfinity/omarchy-privacy.git --enable
```

The **mic toggle works immediately**. For the **webcam toggle**, run the
one-time root setup (the panel also copies this command to your clipboard):

```sh
sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/setup_udev.sh
```

Update with `omarchy plugin update io.github.grootaiinfinity.privacy`. After an
update that moved the folder, re-run `setup_udev.sh` so the webcam restore
service points at the new path.

## Uninstall

If you ran the root setup, undo it **before** removing the plugin — the udev
rule, the restore service and `/var/lib/privacy-bar` live outside the plugin
folder and `omarchy plugin remove` does not touch them:

```sh
sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/uninstall_udev.sh
omarchy plugin remove io.github.grootaiinfinity.privacy
```

`uninstall_udev.sh` re-authorises the camera first (so a camera left toggled
off does not stay off once the restore service is gone), then removes
`/etc/udev/rules.d/99-webcam-toggle.rules`,
`/etc/systemd/system/privacy-webcam-restore.service` and `/var/lib/privacy-bar`,
and reloads systemd and udev. Your own `~/.config/privacy-bar/webcam.conf` is
left alone.

If you never ran `setup_udev.sh`, then
`omarchy plugin remove io.github.grootaiinfinity.privacy` is all you need.

## One-time root setup

`setup_udev.sh` (run with `sudo`):

- auto-detects the webcam (first USB device exposing a UVC video interface),
- installs `/etc/udev/rules.d/99-webcam-toggle.rules` so members of the `wheel`
  group can write the device's `authorized` attribute,
- installs a systemd unit that runs `webcam-restore.sh` on device add to
  re-apply the last saved state (the detected USB id is baked into the unit's
  environment so early-boot lookups are deterministic),
- creates `/var/lib/privacy-bar/` for the saved state.

## Configuration

Auto-detection covers the common single-webcam laptop. Override it with a
`webcam.conf` (see `webcam.conf.example`):

```sh
mkdir -p ~/.config/privacy-bar
printf 'WEBCAM_USB_ID=13d3:56a2\n' > ~/.config/privacy-bar/webcam.conf
# re-run after changing webcam.conf
sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/setup_udev.sh
```

- `WEBCAM_USB_ID=VID:PID` — pick a specific camera (from `lsusb`), e.g. when the
  machine has both an RGB and an IR camera.
- `WEBCAM_GROUP=wheel` — the group granted write access (default `wheel`).

Both are also read from the environment, so
`WEBCAM_USB_ID=... sudo -E setup_udev.sh` works too.

## Notes

- Paths are resolved relative to the installed plugin folder — no username is
  hard-coded. `privacy.qml` finds its backend via `Qt.resolvedUrl(".")`;
  `setup_udev.sh` bakes its own directory into the systemd unit.
- `omarchy update` / `omarchy refresh shell` rewrites `shell.json` and drops the
  `privacy` layout entry (widget files survive). Re-run
  `omarchy plugin enable io.github.grootaiinfinity.privacy` and `omarchy restart shell`.
- After an `omarchy plugin update` that relocates the folder, re-run
  `setup_udev.sh` so the restore service points at the new path.

## License

MIT
