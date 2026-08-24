#!/usr/bin/env zsh
#
# setup_hdd_docker_mount.zsh — auto-mount an extra disk at boot, then restart
# every Docker container that bind-mounts from it.
#
# Docker starts containers before a slow USB disk finishes mounting, so they
# bind an empty mount point and never see the disk. This script writes an
# /etc/fstab entry (nofail) plus a systemd guard that restarts the affected
# containers on every (re)mount. The guard finds containers by their bind-mount
# SOURCE, so new containers need no config.
#
# Self-contained: copy this one file anywhere and run it with sudo.
# Idempotent and safe to re-run.
#
# Usage:
#   sudo ./setup_hdd_docker_mount.zsh <device|UUID=...|LABEL=...> [mount-point]
#
#   sudo ./setup_hdd_docker_mount.zsh /dev/sdb
#   sudo ./setup_hdd_docker_mount.zsh UUID=7d8d589e-32d7-41b3-ad67-989dd33bca5f
#   sudo ./setup_hdd_docker_mount.zsh LABEL=HDD /mnt/hdd
#
# Inputs:
#   $1  disk spec — /dev/sdX, UUID=..., or LABEL=...  (required)
#   $2  mount point (default /mnt/hdd)
#
# Find the device, UUID, and LABEL with `lsblk -f` or `sudo blkid`.
#
# Prefer a LABEL: a reformat regenerates the UUID, but you re-apply the same
# label yourself (ext2/3/4: `sudo e2label /dev/sdb HDD`).

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
# Step 2 deletes the fstab line for $MOUNT_POINT. For "/" that leaves the box
# unbootable.
MOUNT_POINT="${MOUNT_POINT%/}"; : "${MOUNT_POINT:=/}"
if [[ "$MOUNT_POINT" == "/" ]]; then
    echo "ERROR: refusing to manage '/' — pass a dedicated mount point (e.g. /mnt/hdd)."
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

# mountpoint(1) only proves the path is occupied, not that the right disk is
# behind it. Compare UUIDs so a stale or hand-mounted device fails loudly.
if mountpoint -q "$MOUNT_POINT"; then
    ACTUAL_DEV="$(findmnt -no SOURCE "$MOUNT_POINT" 2>/dev/null || true)"
    ACTUAL_UUID="$(blkid -s UUID -o value "$ACTUAL_DEV" 2>/dev/null || true)"
    if [[ -n "$UUID" && "$ACTUAL_UUID" != "$UUID" ]]; then
        echo "ERROR: $MOUNT_POINT holds $ACTUAL_DEV (UUID=${ACTUAL_UUID:-none}),"
        echo "       but $FSTAB_ID is UUID=$UUID. Unmount the wrong disk first:"
        echo "         sudo umount $MOUNT_POINT && sudo mount $MOUNT_POINT"
        exit 1
    fi
    echo "   $MOUNT_POINT is mounted ($ACTUAL_DEV)."

    # Some containers bind a SUBDIRECTORY of the disk (mediamtx uses
    # /mnt/hdd/footage/recordings). If the disk is late, Docker creates that
    # path on the root filesystem and the container writes there. The mount
    # then hides those files, so they leak root-disk space. Look underneath.
    SHADOW_DIR="$(mktemp -d)"
    if mount --bind / "$SHADOW_DIR" 2>/dev/null; then
        if [[ -n "$(find "$SHADOW_DIR$MOUNT_POINT" -mindepth 1 -print -quit 2>/dev/null || true)" ]]; then
            echo "   WARNING: the root disk holds hidden data under $MOUNT_POINT"
            echo "            ($(du -sh "$SHADOW_DIR$MOUNT_POINT" 2>/dev/null | cut -f1) written while the disk was absent)."
            echo "            Inspect and delete it with:"
            echo "              sudo mkdir -p /mnt/root && sudo mount --bind / /mnt/root"
            echo "              sudo du -sh /mnt/root$MOUNT_POINT/*"
            echo "              sudo umount /mnt/root"
        fi
        umount "$SHADOW_DIR" 2>/dev/null || true
    fi
    rmdir "$SHADOW_DIR" 2>/dev/null || true
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
# Restart every RUNNING container whose bind-mount source is at or under $1, so
# it re-binds the now-populated disk. Container names are never hard-coded.
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
else
    echo "restart-hdd-containers: restarting -> ${TARGETS[*]}"
    docker restart "${TARGETS[@]}"
fi

# The loop above skips stopped containers on purpose: starting one could
# resurrect a container you stopped deliberately. Log them instead, so a
# container that is down at boot is visible in the journal.
# This cannot see a broken `devices:` entry — those are not .Mounts. Address
# disks by /dev/disk/by-id in compose to avoid that failure.
for id in $(docker ps -aq --filter status=exited --filter status=created); do
    if docker inspect "$id" --format '{{range .Mounts}}{{println .Source}}{{end}}' 2>/dev/null \
         | grep -qE "^${MP}(/|$)"; then
        name="$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')"
        echo "restart-hdd-containers: WARNING $name binds $MP but is not running" \
             "(exit $(docker inspect -f '{{.State.ExitCode}}' "$id"): $(docker inspect -f '{{.State.Error}}' "$id"))"
    fi
done
HELPER
chmod 0755 /usr/local/sbin/restart-hdd-containers.sh
echo "   installed."

#----------------------------------------------------------------------
# 4) systemd guard: run the helper whenever the disk (re)mounts
#----------------------------------------------------------------------

echo "\n4) Installing + enabling hdd-docker-guard.service..."

# /mnt/hdd -> mnt-hdd.mount, the auto-generated unit for this mount point.
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
# Start whenever the mount unit activates: boot and later manual mounts.
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
