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
rule, the restore service, `/usr/local/lib/omarchy-privacy` and
`/var/lib/omarchy-privacy` live outside the plugin folder and
`omarchy plugin remove` does not touch them:

```sh
sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/uninstall_udev.sh
omarchy plugin remove io.github.grootaiinfinity.privacy
```

`uninstall_udev.sh` re-authorises the camera first (so a camera left toggled
off does not stay off once the restore service is gone), then removes
`/etc/udev/rules.d/99-omarchy-privacy-webcam.rules`,
`/etc/systemd/system/omarchy-privacy-webcam-restore.service`,
`/usr/local/lib/omarchy-privacy` and `/var/lib/omarchy-privacy`, and reloads
systemd and udev. Each of those is
removed only if it carries this plugin's marker line, so a same-named file
belonging to something else is left where it is. Your own
`~/.config/omarchy-privacy/webcam.conf` is left alone.

If you never ran `setup_udev.sh`, then
`omarchy plugin remove io.github.grootaiinfinity.privacy` is all you need.

## One-time root setup

`setup_udev.sh` (run with `sudo`):

- auto-detects the webcam (first USB device exposing a UVC video interface),
- installs `/etc/udev/rules.d/99-omarchy-privacy-webcam.rules` so members of
  the `wheel` group can write the device's `authorized` attribute — that is
  every member of the group, not only the user who ran the setup,
- installs root-owned copies of `webcam-restore.sh` and `webcam-lib.sh` into
  `/usr/local/lib/omarchy-privacy/` (root:root, 0755/0644) and verifies their
  ownership and mode before anything is pointed at them,
- installs a systemd unit that runs that installed copy on device add to
  re-apply the last saved state (the detected USB id is baked into the unit's
  environment so early-boot lookups are deterministic),
- creates `/var/lib/omarchy-privacy/` for the saved state.

The plugin checkout lives in your home directory and is writable by you, so
nothing root runs is ever executed from it: the unit and the udev trigger point
only at `/usr/local/lib/omarchy-privacy/`. `webcam-restore.sh` re-checks this
at run time and refuses to run as root from a path that is not root-owned, or
that has a directory above it writable by others.

Both files it writes into `/etc` carry a
`# managed by the io.github.grootaiinfinity.privacy plugin` marker line, and an
existing file at either path without that marker is never overwritten: the
setup stops and names it (`PRIVACY_FORCE=1` overrides). Upgrading from a
pre-1.1 install migrates the older, un-namespaced
`99-webcam-toggle.rules` / `privacy-webcam-restore.service` /
`/var/lib/privacy-bar` across, keeping the saved camera state.

## Configuration

Auto-detection covers the common single-webcam laptop. Override it with a
`webcam.conf` (see `webcam.conf.example`):

```sh
mkdir -p ~/.config/omarchy-privacy
printf 'WEBCAM_USB_ID=13d3:56a2\n' > ~/.config/omarchy-privacy/webcam.conf
# re-run after changing webcam.conf
sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/setup_udev.sh
```

- `WEBCAM_USB_ID=VID:PID` — pick a specific camera (from `lsusb`), e.g. when the
  machine has both an RGB and an IR camera.
- `WEBCAM_GROUP=wheel` — the group granted write access (default `wheel`).

Both are also read from the environment, so
`WEBCAM_USB_ID=... sudo -E setup_udev.sh` works too.

`webcam.conf` is **parsed, never sourced** — only a literal `VID:PID` is taken
from it, and anything else in the file is ignored rather than executed. The
restore service, which runs as root without a user present, does not read it at
all; it uses the USB id baked into the unit and the root-owned id file under
`/var/lib/omarchy-privacy/`.

## Security model

- The bar widget and `privacy-control.sh` run **unprivileged**. Muting the mic
  is `wpctl`; switching the camera is a write to the USB device's `authorized`
  attribute, made possible by the group permission the udev rule grants. No
  privilege escalation, and no setuid helper, is involved at run time.
- Root runs only two things, both installed by `setup_udev.sh` into
  `/usr/local/lib/omarchy-privacy/` as root:root and verified there before the
  unit is written: `webcam-restore.sh` and the `webcam-lib.sh` it loads. Nothing
  under the user's home is ever executed or sourced by root, and
  `webcam-restore.sh` enforces that itself at run time.
- `webcam.conf` is parsed for a literal `VID:PID` and never executed, so a
  config file in a user's home cannot become code in a root context.
- The restore unit runs with `NoNewPrivileges`, `ProtectHome`, `PrivateTmp`,
  `RestrictNamespaces`, `MemoryDenyWriteExecute` and related confinement.
- The saved state file is validated on read: anything other than `0` or `1` is
  ignored and the camera defaults to on.

## Notes

- **Upgrading to 1.2.0 — re-run `setup_udev.sh`.** Earlier versions pointed the
  restore service and the udev trigger at `webcam-restore.sh` inside the plugin
  checkout, and that script loaded `webcam-lib.sh` from the same place. Both
  live in your home directory, so anything able to write there could have code
  run as root at the next boot or camera replug. 1.2.0 installs root-owned
  copies under `/usr/local/lib/omarchy-privacy/` and points the unit there
  instead. An existing install keeps the old, vulnerable unit until setup is
  re-run:
  `sudo ~/.config/omarchy/plugins/io.github.grootaiinfinity.privacy/setup_udev.sh`
- Paths are resolved relative to the installed plugin folder — no username is
  hard-coded. `privacy.qml` finds its backend via `Qt.resolvedUrl(".")`. The
  root-executed half is installed to `/usr/local/lib/omarchy-privacy/` and the
  systemd unit names that path.
- `omarchy update` / `omarchy refresh shell` rewrites `shell.json` and drops the
  `privacy` layout entry (widget files survive). Re-run
  `omarchy plugin enable io.github.grootaiinfinity.privacy` and `omarchy restart shell`.
- After an `omarchy plugin update` that changes what the root-executed scripts
  do, re-run `setup_udev.sh` so the installed copies under
  `/usr/local/lib/omarchy-privacy/` are refreshed.

## License

MIT
