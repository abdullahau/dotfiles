# iPhone MVT scan: step by step

How to run a scan from start to finish. To install the tools, see [`mvt/README.md`](../mvt/README.md) (`./mvt/install.sh`).

Working folders used below (anywhere outside the dotfiles is fine):

```fish
mkdir -p ~/ios-scan/{backup,decrypted,results}
```

| Folder | Holds |
|---|---|
| `~/ios-scan/backup` | encrypted backup from `idevicebackup2` |
| `~/ios-scan/decrypted` | decrypted copy, made by `mvt-ios decrypt-backup` |
| `~/ios-scan/results` | results from `mvt-ios check-backup` |

## 1. Connect and pair
Plug in the iPhone, unlock it, and tap **Trust** when it asks.

```fish
sudo dmesg -w                    # optional, in a second terminal: USB events as you plug in
idevice_id -l                    # prints the UDID; nothing = see Troubleshooting
idevicepair validate             # SUCCESS = paired. If not: idevicepair pair, then tap Trust
ideviceinfo -k ProductVersion    # iOS version (write it down for the report)
ideviceinfo                      # full device info; -s = "simple" mode, skips auto-pairing
ideviceinstaller list            # installed apps
```

## 2. Live logs (optional)
Use these to watch what the phone is doing right now. They're not part of the MVT check.

```fish
idevicesyslog pidlist                          # PID and name of every running process
idevicesyslog -q                               # live log without the noisy system processes
idevicesyslog -p botim_ios                     # one app; get the exact name: idevicesyslog pidlist | grep -i botim
idevicesyslog -p 'locationd|backboardd|SpringBoard'   # motion and orientation (see below)
idevicesyslog -o ~/ios-scan/syslog.txt         # save to a file instead
```
`SpringBoard` (home screen) only logs screen rotation. Motion sensor (CoreMotion) activity is mostly logged by `locationd`, and sensor and orientation events by `backboardd`.

## 3. Encrypted backup
An encrypted backup includes more data than an unencrypted one (health data, keychain, call history), so always encrypt it.

```fish
idevicebackup2 -i encryption on                      # once per phone: choose a backup password, then enter the passcode on the phone
idevicebackup2 backup --full ~/ios-scan/backup       # keep the phone unlocked and plugged in until it finishes
ls ~/ios-scan/backup                                 # the backup is in a <UDID> subfolder
```
**Write down the backup password.** You need it in step 5, and nobody can recover it if you lose it.
If `encryption on` says encryption is already on, someone set a password before. Use that password, or reset it on the phone (Settings → General → Transfer or Reset → Reset All Settings).

## 4. Update indicators (IOCs)
```fish
mvt-ios download-iocs
```

## 5. Decrypt
```fish
mvt-ios decrypt-backup -d ~/ios-scan/decrypted ~/ios-scan/backup/<UDID>
```
Point it at the `<UDID>` subfolder, not `backup/`. It asks for the backup password. To skip the prompt in fish: `set -x MVT_IOS_BACKUP_PASSWORD '…'`.

## 6. Scan
```fish
mvt-ios check-backup -o ~/ios-scan/results ~/ios-scan/decrypted
```
The IOCs from step 4 load automatically. To add your own indicator files, pass `-i extra.stix2` (repeatable).

## 7. Read the results
```fish
cd ~/ios-scan/results
grep -iE 'warning|detected' command.log           # the run log: anything flagged shows up here
ls *_detected.json                                # one file per module that matched an IOC
column -s, -t < timeline_detected.csv | less -S   # IOC matches only, in time order
column -s, -t < timeline.csv | less -S            # every event, in time order
jq . safari_history.json | less                   # any module's full output (sms, calls, apps, …)
```
**No `*_detected.json` files and no `timeline_detected.csv`** means nothing matched a known indicator. That's not proof the phone is clean, only that no current IOC matched.

## Afterwards
The backup and decrypted folders contain the phone's private data (messages, photos, keychain). Keep them only while you need them:
```fish
rm -rf ~/ios-scan/backup ~/ios-scan/decrypted
```

## Troubleshooting
| Problem | Fix |
|---|---|
| `idevice_id -l` prints nothing | Unlock the phone and check for the Trust prompt. Then `sudo systemctl restart usbmuxd`. `usbmuxd` shows inactive until a phone is plugged in, which is normal. |
| `idevicepair validate` fails | `idevicepair unpair && idevicepair pair`, then tap Trust again |
| `mvt-ios: command not found` | `fish_add_path ~/.local/bin` (that's where `uv tool` installs it) |
| Backup stops partway | Keep the phone unlocked, use a different cable or port, run `backup --full` again |
