#!/usr/bin/env zsh
#
# setup_rclone.zsh — render ~/.config/rclone/rclone.conf from a committed
# template plus the gitignored secret in the repo-root .env.
#
# WHY this exists instead of symlinking rclone/ into ~/.config:
#
#   1. rclone.conf holds a live OneDrive OAuth token (access + refresh). That is
#      a credential, and this repo is pushed to GitHub. It must never be tracked.
#
#   2. rclone REWRITES rclone.conf in place every time it refreshes the access
#      token (roughly hourly during a sync). If ~/.config/rclone is a symlink to
#      the repo, every refresh dirties the working tree and re-stages the secret.
#      So the live config has to be a real file OUTSIDE the repo that rclone owns.
#
# The split is therefore:
#
#   rclone/rclone-filters.txt    tracked, symlinked  -> ~/.config/rclone/
#   rclone/rclone.conf.template  tracked, no secrets -> rendered
#   .env (repo root)             gitignored secret   -> substituted in
#   ~/.config/rclone/rclone.conf real file, rclone-owned, never touched again
#
# .env is a BOOTSTRAP SEED, not the source of truth. Once rendered, rclone rotates
# the token in the live file and .env goes stale — that is expected and fine. It
# only has to be fresh enough to authenticate once on a new machine. If the seed
# ever goes too stale to refresh, re-run `rclone config reconnect onedrive:` and
# re-seed with `./setup_rclone.zsh --export`.
#
# Idempotent and safe to re-run.
#
# Usage:
#   ./setup_rclone.zsh            # link filters; render conf only if missing
#   ./setup_rclone.zsh --force    # re-render conf from .env, clobbering the live one
#   ./setup_rclone.zsh --export   # print current live token as .env lines (re-seed)

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
    # Rescue the already-authenticated config out of the repo working tree.
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
        [[ "$line" == '#'* ]] && continue          # drop template-only docs
        line="${line//\$\{ONEDRIVE_TOKEN\}/$ONEDRIVE_TOKEN}"
        line="${line//\$\{ONEDRIVE_DRIVE_ID\}/$ONEDRIVE_DRIVE_ID}"
        print -r -- "$line"
    done < "$TEMPLATE"
} > "$CONF"
chmod 600 "$CONF"

echo "   wrote $CONF (0600)"
echo "\n<<< done >>>\n"
echo "Verify with:  rclone lsd onedrive:"
