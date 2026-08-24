#!/usr/bin/env zsh
#
# setup_rclone.zsh — render ~/.config/rclone/rclone.conf from a tracked template
# plus the gitignored secret in the repo-root .env.
#
# ~/.config/rclone is NOT symlinked into this repo, for two reasons:
#   1. rclone.conf holds a live OneDrive OAuth token. This repo is public.
#   2. rclone rewrites rclone.conf in place on every token refresh (about
#      hourly during a sync), which would dirty the working tree each time.
#
# The layout is:
#   rclone/rclone-filters.txt    tracked, symlinked -> ~/.config/rclone/
#   rclone/rclone.conf.template  tracked, no secrets -> rendered
#   .env (repo root)             gitignored secret  -> substituted in
#   ~/.config/rclone/rclone.conf real file, owned by rclone
#
# .env is a bootstrap seed, not the source of truth. It only has to be fresh
# enough to authenticate once on a new machine. If it goes too stale, run
# `rclone config reconnect onedrive:` then `./setup_rclone.zsh --export`.
#
# Idempotent and safe to re-run.
#
# Inputs:
#   .env at the repo root, with ONEDRIVE_TOKEN and ONEDRIVE_DRIVE_ID.
#
# Usage:
#   ./setup_rclone.zsh            # link filters; render conf only if missing
#   ./setup_rclone.zsh --force    # re-render conf from .env, clobbering the live one
#   ./setup_rclone.zsh --export   # print the live token as .env lines (re-seed)

setopt errexit nounset pipefail

REPO="${0:A:h}"
SRC="$REPO/rclone"
DEST="$HOME/.config/rclone"
CONF="$DEST/rclone.conf"
TEMPLATE="$SRC/rclone.conf.template"
ENV_FILE="$REPO/.env"

MODE="${1:-}"

#----------------------------------------------------------------------
# --export: dump the live credential back out as .env lines
#----------------------------------------------------------------------

if [[ "$MODE" == "--export" ]]; then
    if [[ ! -f "$CONF" ]]; then
        echo "ERROR: no live config at $CONF to export from." >&2
        exit 1
    fi
    print -r -- "ONEDRIVE_TOKEN='$(sed -n 's/^token *= *//p' "$CONF" | head -1)'"
    print -r -- "ONEDRIVE_DRIVE_ID='$(sed -n 's/^drive_id *= *//p' "$CONF" | head -1)'"
    exit 0
fi

echo "\n<<< rclone config (secret-free tracking) >>>\n"

#----------------------------------------------------------------------
# 1) Replace a legacy ~/.config/rclone symlink with a real directory
#----------------------------------------------------------------------

echo "1) Preparing $DEST ..."

if [[ -L "$DEST" ]]; then
    echo "   found legacy symlink -> ${DEST:A}, migrating to a real directory"
    LEGACY_CONF="${DEST:A}/rclone.conf"
    rm "$DEST"
    mkdir -p "$DEST"
    # Rescue the authenticated config out of the repo working tree.
    if [[ -f "$LEGACY_CONF" ]]; then
        mv "$LEGACY_CONF" "$CONF"
        echo "   moved $LEGACY_CONF -> $CONF (out of the repo)"
    fi
else
    mkdir -p "$DEST"
fi
chmod 700 "$DEST"

#----------------------------------------------------------------------
# 2) Symlink the filter list (not a secret, safe to track)
#----------------------------------------------------------------------

echo "2) Linking rclone-filters.txt ..."
ln -sfn "$SRC/rclone-filters.txt" "$DEST/rclone-filters.txt"

#----------------------------------------------------------------------
# 3) Render rclone.conf from template + .env, only if there isn't one
#----------------------------------------------------------------------

echo "3) Rendering rclone.conf ..."

if [[ -f "$CONF" && "$MODE" != "--force" ]]; then
    echo "   $CONF already exists — leaving it alone (rclone owns it)."
    echo "   Use --force to re-render from .env."
    echo "\n<<< done >>>\n"
    exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found." >&2
    echo "  cp $REPO/.env.example $ENV_FILE   and fill in the token." >&2
    exit 1
fi

ONEDRIVE_TOKEN=""
ONEDRIVE_DRIVE_ID=""
source "$ENV_FILE"

if [[ -z "$ONEDRIVE_TOKEN" || "$ONEDRIVE_TOKEN" == *'"..."'* ]]; then
    echo "ERROR: ONEDRIVE_TOKEN is unset or still the placeholder in $ENV_FILE." >&2
    exit 1
fi

umask 077
{
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == '#'* ]] && continue          # drop template docs
        line="${line//\$\{ONEDRIVE_TOKEN\}/$ONEDRIVE_TOKEN}"
        line="${line//\$\{ONEDRIVE_DRIVE_ID\}/$ONEDRIVE_DRIVE_ID}"
        print -r -- "$line"
    done < "$TEMPLATE"
} > "$CONF"
chmod 600 "$CONF"

echo "   wrote $CONF (0600)"
echo "\n<<< done >>>\n"
echo "Verify with:  rclone lsd onedrive:"
