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
- A USB webcam, and one-time root setup for non-root access to its
  `authorized` attribute (see below)

## Install

```sh
omarchy plugin add https://github.com/GrootAiInfinity/omarchy-privacy.git --enable
```

The **mic toggle works immediately**. For the **webcam toggle**, run the
one-time root setup (the panel also copies this command to your clipboard):

```sh
sudo ~/.config/omarchy/plugins/groot.privacy/setup_udev.sh
```

Remove with `omarchy plugin remove groot.privacy`; update with
`omarchy plugin update groot.privacy`. After an update that moved the folder,
re-run `setup_udev.sh` so the webcam restore service points at the new path.

## One-time root setup

`setup_udev.sh` (run with `sudo`):

- locates the webcam by USB vendor:product id,
- installs `/etc/udev/rules.d/99-webcam-toggle.rules` so members of the `wheel`
  group can write the device's `authorized` attribute,
- installs a systemd unit that runs `webcam-restore.sh` on device add to
  re-apply the last saved state,
- creates `/var/lib/privacy-bar/` for the saved state.

## Notes

- **The webcam is identified by a hard-coded USB id** (`13d3:56a2`,
  "USB2.0 HD UVC WebCam") in `privacy-control.sh`, `webcam-restore.sh`, and the
  udev rule. Change these three to match your camera (`lsusb`).
- Absolute paths are hard-coded as `/home/groot/…` in `privacy.qml` (the
  `privacy-control.sh` location) and in `setup_udev.sh` (`RESTORE_SCRIPT`).
  Edit both if your username isn't `groot`.
- `omarchy update` / `omarchy refresh shell` rewrites `shell.json` and drops the
  `privacy` layout entry (widget files survive). Re-add it and
  `omarchy restart shell`.

## License

MIT
