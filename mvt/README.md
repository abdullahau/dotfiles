# mvt: iPhone tools (libimobiledevice) + MVT

`./mvt/install.sh` installs and checks:

| Package | From |
|---|---|
| libplist, libimobiledevice-glue, libusbmuxd, usbmuxd, libtatsu, libimobiledevice, ifuse | official repos (pacman) |
| libirecovery, libideviceactivation, ideviceinstaller-git | AUR (paru) |
| idevicerestore-git | built here from `idevicerestore-git/PKGBUILD` |
| mvt (`mvt-ios`, `mvt-android`) | `uv tool install` |

`./mvt/install.sh --rebuild` also rebuilds idevicerestore from the latest upstream code. Do this every few months, or after Apple changes the restore process.

## Why it's set up this way
- **No `-git` libraries.** `libplist-git` ships `libplist-2.0.so.12`, but every repo package (including `upower`) was built against `.so.4`.
  Installing it broke `ideviceinfo`, `ifuse` and `usbmuxd`. The script removes any `-git` library it finds and reinstalls the repo version.
- **idevicerestore** 1.0.0 (2019, the AUR `idevicerestore` package) no longer builds against libirecovery ≥ 1.1 (`irecv_init` was removed).
  The AUR `idevicerestore-git` package pulls in the whole `-git` library stack. `idevicerestore-git/PKGBUILD` is that package's build script
  with its dependencies switched to the repo libraries, which current upstream supports (libplist ≥ 2.6, libimobiledevice ≥ 1.4, libirecovery ≥ 1.3).
- **`IgnorePkg = idevicerestore-git`** in `/etc/pacman.conf` (added by the script) stops `paru -Syu` from replacing the local build with the AUR one.
- **ideviceinstaller-git** (1.2.0) is used because the AUR `ideviceinstaller` is 1.1.1. It only depends on repo packages, so it's safe.

## Updating
- `paru -Syu` updates everything except idevicerestore. Then run `./mvt/install.sh --rebuild` for idevicerestore.
- `uv tool upgrade mvt` (also done by the script).

## Using it
```fish
idevice_id -l                # device UDID (phone unlocked, "Trust" tapped)
idevicepair validate         # SUCCESS = paired
ideviceinfo -k ProductVersion
ideviceinstaller list        # installed apps

# MVT: encrypted backup, then decrypt, then check
idevicebackup2 -i encryption on                  # once; sets a backup password
idevicebackup2 backup --full ~/ios-backup
mvt-ios decrypt-backup -d ~/ios-backup-dec ~/ios-backup/<UDID>
mvt-ios download-iocs
mvt-ios check-backup -o ~/mvt-results ~/ios-backup-dec
```
`usbmuxd` shows as inactive until a device is plugged in (udev starts it). If `idevice_id -l` shows nothing, run `sudo systemctl restart usbmuxd`.
