# Plan B

No terminal, no custom firmware: Bespok3d ships neither, and neither does this plugin. It asks the U1's
stock updater to install paxx12's [Extended Firmware](https://github.com/paxx12/SnapmakerU1) from the
Bespok3d app, without a USB stick, and boots into it. The system you were running stays in the other slot.

> **Status: untested on a printer.** Everything below is what the scripts do against fakes. Do not set
> Mode to `flash` on a printer you cannot recover over USB.

## How the U1 stores its system

The U1's eMMC holds two copies of the bootloader, kernel and root filesystem: `uboot_a`/`uboot_b`,
`boot_a`/`boot_b` and `system_a`/`system_b`. Only one slot runs at a time. The stock updater installs a new
firmware by writing the slot that is not running, marking it active, and rebooting. At boot,
`/etc/init.d/S99_bootcontrol` commits whichever slot came up.

## What it does

On install (and at every boot until it has written the package once), the `u1-plan-b` service:

1. Reads the running slot from `/proc/cmdline` and refuses if there is none.
2. Asks Moonraker for the print state and refuses unless it is `standby`, `complete`, `cancelled` or
   `error`.
3. Checks there is about 700 MB free under `/userdata`.
4. Downloads the release named by **Image URL** (only `github.com/paxx12/SnapmakerU1/releases/download/`
   URLs ending in `_upgrade.bin` are accepted) and checks it against **SHA-256**.
5. Extracts `update.img` with the stock `upfileUnpack`.
6. In `dry-run` mode, logs what it would do and stops here.
7. In `flash` mode, runs the stock `updateEngine --image_url=<update.img> --update`, removes
   `/oem/.printer_data` and `/oem/.debug` exactly as the stock updater does before activating a new
   system, records that this package was written, and reboots.

The MCUs are not flashed by this plugin. The new system's Klipper start script runs the stock
`systemUpgrade.sh check-restore` at boot, which flashes the MCU firmware that system ships with.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `PAXX_MODE` | `dry-run` | `dry-run` checks and downloads only; `flash` writes the other slot and reboots |
| `PAXX_URL` | the v1.6.0-paxx12-22 release asset | the `_upgrade.bin` to install |
| `PAXX_SHA256` | none, required | sha256 of that file, from the release page |

## Going back

Over SSH, as root:

```sh
/userdata/bespok3d/bin/plan-b-flipback --yes
```

It marks the other slot active with the stock `updateEngine --misc=other` and reboots. This only works
while the other slot still holds the system you left: any later firmware update overwrites it.

## Things to know

- **Logs** are in `/userdata/bespok3d/var/log/u1-plan-b.log`.
- `/oem/.debug` is removed on `flash`, as every stock firmware update does, so persisted `/etc` changes
  are reset.
- Whether Bespok3d itself is still running after the reboot into Extended Firmware is not yet verified.
