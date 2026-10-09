# u1-plan-b

No terminal, no custom firmware. A [Bespok3d](https://github.com/Bespok3d) plugin that politely asks the
Snapmaker U1's stock updater to install paxx12's Extended Firmware on the spare A/B slot, then boots into
it. Technically compliant.

The user-facing documentation is in [`doc/README.md`](doc/README.md).

## Layout

Modelled on [u1-force-ssh](https://github.com/justinh-rahb/u1-force-ssh):

```text
manifest.json              one managed root service, two system-bin scripts, three settings
files/bin/plan-b-run      download, verify, unpack, write the other slot, reboot
files/bin/plan-b-flipback mark the other slot active and reboot (manual, over SSH)
tests/run.sh               shell tests against fake updateEngine, upfileUnpack, curl, df and reboot
doc/                       README, CHANGELOG, ATTRIBUTIONS, LICENSE shipped with the plugin
scripts/check.sh           the gate: tests plus the shared Bespok3d detectors (lib_bespok3d)
```

## Test

```sh
TEST_SH=dash dash tests/run.sh
docker run --rm -v "$PWD:/p:ro" -e TEST_SH="busybox ash" alpine:3.20 busybox ash /p/tests/run.sh
```

`TEST_SH` is the shell the scripts under test run in, so both lines exercise them in the printer's shells.

## Where the A/B behaviour comes from

Read from the stock `U1_2.0.0` root filesystem the Extended Firmware build extracts
(`tmp/firmware/rootfs` in a local SnapmakerU1-Extended-Firmware checkout), not from a running printer:

- `parameter.txt` lays out `uboot_a/_b`, `misc`, `boot_a/_b`, `system_a/_b`, `oem`, `userdata`.
- `/home/lava/bin/systemUpgrade.sh`, `upgrade_soc`: reads `android_slotsufix` or
  `androidboot.slot_suffix` from `/proc/cmdline`, runs `updateEngine --image_url=<update.img> --update`
  ("upgrade $slot_other and reboot to active"), removes `/oem/.printer_data` and `/oem/.debug`, reboots.
  `plan-b-run` runs the same sequence.
- `updateEngine` usage text: `--misc=now` (set the current slot bootable), `--misc=other` (set the other
  slot bootable), `--misc=display`, `--partition=<mask>`, `--update`.
- `/etc/init.d/S99_bootcontrol` runs `updateEngine --misc=now` at every boot, committing the slot that
  came up.
- `/etc/init.d/S60klipper` runs `systemUpgrade.sh check-restore`, which reflashes the MCUs to the
  firmware the booted system ships with. That is why the plugin writes only the SoC image.
- paxx's own `scripts/dev/upgrade-firmware.sh` installs a dev build the same way:
  `systemUpgrade.sh upgrade soc /userdata/update.img`.

## Open questions before a printer test

1. Does `updateEngine --update` with no `--partition` write only the inactive slot? `systemUpgrade.sh`
   relies on it, but its default mask is not documented. Running `updateEngine --misc=display` before
   and after on a printer would confirm the slot flags.
2. Does Bespok3d's boot hook survive a new rootfs plus the `/oem/.debug` removal? If not, the plugin
   still does its job but Bespok3d needs reinstalling on Extended Firmware.
3. Should the default image track paxx's latest release instead of a pinned one? Pinned for now so the
   sha256 setting always matches the default URL.
4. The manifest's `requires.variables` only uses `name`, `required` and `default`, the fields the daemon
   tests show. Labels and a dropdown for `PAXX_MODE` depend on what the app supports.

## Build and sideload

```sh
git submodule update --init --recursive
bash scripts/check.sh
npx github:Bespok3d/b3-builder build --unit plugin --source . --out dist --atom-repo justinh-rahb/u1-plan-b
```

## Licence

GPL-3.0, see [LICENSE](LICENSE).
