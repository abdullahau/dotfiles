#!/usr/bin/env zsh
#
# setup_hdd_docker_mount.zsh — zsh, self-contained (no .env/brew). Copy this ONE
# file anywhere and run it with sudo.
#
# Makes an external/extra disk auto-mount at boot AND ensures every Docker
# container that bind-mounts from it gets (re)started once the disk is actually
# mounted — for plex, transmission, motioneye, and anything future.
#
# WHY: Docker bind mounts are rprivate. On boot, dockerd starts containers
# (restart: unless-stopped) BEFORE a slow USB disk is mounted, so they bind an
# EMPTY mountpoint and never see the disk until restarted. This wires up:
#   A) an /etc/fstab entry (by UUID or LABEL, + nofail) so the disk mounts
#      automatically, and
#   B) a systemd guard that restarts the affected containers whenever the disk
#      (re)mounts. The guard discovers containers by their mount SOURCE, so it
#      needs no per-service config and auto-covers any future container.
#
# Idempotent and safe to re-run. Designed for fresh Ubuntu installs too.
#
# Usage:
#   sudo ./setup_hdd_docker_mount.zsh <device|UUID=...|LABEL=...> [mount-point]
# Examples:
#   sudo ./setup_hdd_docker_mount.zsh /dev/sdb
#   sudo ./setup_hdd_docker_mount.zsh UUID=7d8d589e-32d7-41b3-ad67-989dd33bca5f
#   sudo ./setup_hdd_docker_mount.zsh LABEL=HDD /mnt/hdd
#
# Look up the device name (/dev/sdX), UUID, and LABEL with any of:
#   lsblk -f                    # tree -> fs type, LABEL, UUID, mountpoint
#   sudo blkid                  # e.g. /dev/sdb: LABEL="HDD" UUID="..." TYPE="ext4"
#   sudo blkid /dev/sdb         # just that one device
#   lsblk -o NAME,SIZE,TRAN,FSTYPE,LABEL,UUID,MOUNTPOINT   # TRAN shows USB vs SATA
#
# --- Prefer a LABEL if you might ever reformat -------------------------------
# A UUID is regenerated every time you reformat; a LABEL is a name YOU choose and
# re-apply, so mounting by LABEL keeps working across a reformat (just re-label
# afterwards). Set a label ONCE, matching the filesystem type:
#   ext2/3/4 :  sudo e2label /dev/sdb HDD
#   xfs      :  sudo xfs_admin -L HDD /dev/sdb
#   btrfs    :  sudo btrfs filesystem label /dev/sdb HDD
#   exfat    :  sudo exfatlabel /dev/sdb HDD
#   fat/vfat :  sudo fatlabel /dev/sdb HDD
# Verify with `lsblk -f`, then run this script with LABEL=HDD. NOTE: reformatting
# still WIPES the label, so re-apply the SAME label after any reformat.

setopt errexit nounset pipefail

SPEC="${1:-}"
MOUNT_POINT="${2:-/mnt/hdd}"

if [[ -z "$SPEC" ]]; then
    echo "Usage: sudo $0 <device|UUID=...|LABEL=...> [mount-point=/mnt/hdd]"
    echo "  Find the disk with: lsblk -f    (or: sudo blkid)"
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo (it writes /etc/fstab and a systemd unit)."
    exit 1
fi

echo "\n<<< HDD auto-mount + Docker restart guard ($SPEC -> $MOUNT_POINT) >>>\n"

#----------------------------------------------------------------------
# 1) Resolve the block device + the fstab identifier (UUID= or LABEL=)
#----------------------------------------------------------------------

echo "1) Resolving disk identity..."

DEV=""
FSTAB_ID=""
case "$SPEC" in
    /dev/*)
        DEV="$SPEC" ;;                                            # fstab id -> UUID (below)
    UUID=*)
        DEV="$(blkid -U "${SPEC#UUID=}"  2>/dev/null || true)";  FSTAB_ID="$SPEC" ;;
    LABEL=*)
        DEV="$(blkid -L "${SPEC#LABEL=}" 2>/dev/null || true)";  FSTAB_ID="$SPEC" ;;
    *)  # bare value: try it as a UUID first, then as a LABEL
        if DEV="$(blkid -U "$SPEC" 2>/dev/null)"; then
            FSTAB_ID="UUID=$SPEC"
        elif DEV="$(blkid -L "$SPEC" 2>/dev/null)"; then
            FSTAB_ID="LABEL=$SPEC"
        else
            DEV=""
        fi ;;
esac

if [[ -z "$DEV" ]]; then
    echo "ERROR: could not find a disk for '$SPEC'. Is it plugged in? Check: lsblk -f"
    exit 1
fi

UUID="$(blkid -s UUID  -o value "$DEV" 2>/dev/null || true)"
FSTYPE="$(blkid -s TYPE -o value "$DEV" 2>/dev/null || true)"
if [[ -z "$FSTYPE" ]]; then
    echo "ERROR: no filesystem detected on $DEV (format it first?)."
    exit 1
fi
# A device path was given -> default the fstab identifier to the stable UUID.
if [[ -z "$FSTAB_ID" ]]; then
    if [[ -z "$UUID" ]]; then
        echo "ERROR: $DEV has no UUID; pass an explicit LABEL= instead."
        exit 1
    fi
    FSTAB_ID="UUID=$UUID"
fi
echo "   device=$DEV  fstab-id=$FSTAB_ID  fstype=$FSTYPE"

#----------------------------------------------------------------------
# 2) Mount point + /etc/fstab entry (idempotent, nofail)
#----------------------------------------------------------------------

echo "\n2) Writing /etc/fstab entry..."

mkdir -p "$MOUNT_POINT"

# nofail = boot never hangs if the disk is absent. device-timeout = wait a bit
# for a slow USB disk to appear, then move on.
FSTAB_LINE="$FSTAB_ID  $MOUNT_POINT  $FSTYPE  defaults,nofail,x-systemd.device-timeout=30  0  2"

# Replace any prior entry for this mount point (timestamped backup first).
if grep -qE "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab; then
    cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
    sed -i "\#[[:space:]]${MOUNT_POINT}[[:space:]]#d" /etc/fstab
fi
echo "$FSTAB_LINE" >> /etc/fstab
echo "   $FSTAB_LINE"

systemctl daemon-reload
# Activate now (no-op if already mounted). mount -a respects nofail.
mount "$MOUNT_POINT" 2>/dev/null || mount -a 2>/dev/null || true
if mountpoint -q "$MOUNT_POINT"; then
    echo "   $MOUNT_POINT is mounted."
else
    echo "   WARNING: $MOUNT_POINT not mounted (disk absent?)."
fi

#----------------------------------------------------------------------
# 3) Generic restart helper — installed as bash (systemd runs it)
#----------------------------------------------------------------------

echo "\n3) Installing /usr/local/sbin/restart-hdd-containers.sh..."

cat > /usr/local/sbin/restart-hdd-containers.sh <<'HELPER'
#!/usr/bin/env bash
# Managed by setup_hdd_docker_mount.zsh — do not edit by hand.
# Restart every RUNNING container whose bind-mount source is at/under $1 so it
# re-binds the now-populated disk. Discovers containers dynamically — no
# hard-coded service names.
set -euo pipefail
MP="${1:?mount point required}"
command -v docker >/dev/null 2>&1 || exit 0

# Wait until the docker daemon is responsive (up to ~30s) before querying it.
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done

mapfile -t TARGETS < <(
    for id in $(docker ps -q); do
        if docker inspect "$id" --format '{{range .Mounts}}{{println .Source}}{{end}}' 2>/dev/null \
             | grep -qE "^${MP}(/|$)"; then
            docker inspect -f '{{.Name}}' "$id" | sed 's#^/##'
        fi
    done
)
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "restart-hdd-containers: no running container binds $MP"
    exit 0
fi
echo "restart-hdd-containers: restarting -> ${TARGETS[*]}"
docker restart "${TARGETS[@]}"
HELPER
chmod 0755 /usr/local/sbin/restart-hdd-containers.sh
echo "   installed."

#----------------------------------------------------------------------
# 4) systemd guard: run the helper whenever the disk (re)mounts
#----------------------------------------------------------------------

echo "\n4) Installing + enabling hdd-docker-guard.service..."

# /mnt/hdd -> mnt-hdd.mount (the auto-generated unit for this mount point).
MOUNT_UNIT="$(systemd-escape -p --suffix=mount "$MOUNT_POINT")"

cat > /etc/systemd/system/hdd-docker-guard.service <<UNIT
[Unit]
Description=Restart Docker containers bound to $MOUNT_POINT when it (re)mounts
After=docker.service ${MOUNT_UNIT}
Requires=docker.service
RequiresMountsFor=$MOUNT_POINT

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restart-hdd-containers.sh $MOUNT_POINT

[Install]
# Start whenever the mount unit activates — covers boot AND a later manual mount.
WantedBy=${MOUNT_UNIT}
UNIT

systemctl daemon-reload
systemctl enable hdd-docker-guard.service
echo "   enabled (WantedBy=${MOUNT_UNIT})."

#----------------------------------------------------------------------
# 5) Fix the current boot right now
#----------------------------------------------------------------------

echo "\n5) Restarting any currently-affected containers..."
/usr/local/sbin/restart-hdd-containers.sh "$MOUNT_POINT" || true

echo "\n<<< Done >>>"
echo "On every boot (or manual mount of $MOUNT_POINT), containers bound to it auto-restart."
echo "Revert with:"
echo "  sudo systemctl disable --now hdd-docker-guard.service"
echo "  sudo rm /etc/systemd/system/hdd-docker-guard.service /usr/local/sbin/restart-hdd-containers.sh"
print -r -- "  sudo sed -i '\\#[[:space:]]${MOUNT_POINT}[[:space:]]#d' /etc/fstab   # remove the fstab line"
