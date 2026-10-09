# Attributions - u1-paxx-ab

**Plugin author:** justinh-rahb

Downloads paxx12's Extended Firmware and installs it with the U1's own stock updater.

| Upstream project | Author | Licence | Needed at runtime | Code ships in this package |
| --- | --- | --- | --- | --- |
| SnapmakerU1 Extended Firmware | paxx12 and contributors | GPL-3.0 | yes, downloaded at run time | no |
| Snapmaker U1 stock firmware, `updateEngine`, `upfileUnpack`, `systemUpgrade.sh` | Snapmaker | per the firmware | yes | no |

Nothing from either ships in this package: the firmware is downloaded from paxx12's GitHub release you name,
and the plugin calls the updater tools already on the printer.
