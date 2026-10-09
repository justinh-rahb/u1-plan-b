# Changelog

## 0.1.0 (2026-10-09)

Initial scaffold. A root managed service that downloads a paxx12 Extended Firmware release, verifies its
sha256, extracts `update.img` with the stock `upfileUnpack`, and writes it to the non-booted A/B slot with
the stock `updateEngine --image_url=... --update`, the same command `systemUpgrade.sh upgrade soc` runs.
It then clears the same `/oem` flags the stock updater clears and reboots into the new slot. Installs in
`dry-run` mode by default. Also places `plan-b-flipback`, which marks the other slot active
(`updateEngine --misc=other`) and reboots, for going back.

Tested against fake updater tools under dash and BusyBox ash (`tests/run.sh`); never run on a printer.
