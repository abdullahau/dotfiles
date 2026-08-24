#!/usr/bin/env zsh
#
# setup_tailscale_serve.zsh — declare and re-apply the Tailscale Serve map for
# this host.
#
# Serve exposes a LAN-only admin page that cannot run Tailscale itself (the
# D-Link router at 192.168.0.1) on the tailnet over HTTPS, at
# https://<this-host>.<tailnet>.ts.net:<port>. No subnet routing needed.
#
# Serve config lives per-node and the admin console cannot show or edit it, so
# this file is the source of truth in version control.
#
# Serve binds only on the tailscale interface and dials out to the backend. It
# never binds host :80 or :443, which keeps it clear of AdGuard.
#
# Self-contained: copy this one file anywhere and run it.
# Idempotent and safe to re-run.
#
# Usage:
#   ./setup_tailscale_serve.zsh            # apply the SERVE_MAP below
#   ./setup_tailscale_serve.zsh status     # print current serve status
#   ./setup_tailscale_serve.zsh reset      # tear down every port in SERVE_MAP
#
# Run this once so the script never needs sudo again:
#   sudo tailscale set --operator=$USER

# EDIT HERE: <tailnet-https-port> -> <local backend URL>. One line per admin
# page. Use ports 8000-9999. Never 80 or 443: AdGuard holds those on the host
# and the script refuses them.
# The extender is not served on purpose. It is a mesh node with no IPv4, and the
# main router's mesh UI manages it.
typeset -A SERVE_MAP=(
    8443  "http://192.168.0.1:80"      # D-Link DIR-853 main router admin
    # 8081  "http://localhost:3000"    # (example) AdGuard Home UI — enable if wanted
)

setopt nounset pipefail        # NOT errexit: we handle tailscale errors explicitly

#----------------------------------------------------------------------
# tailscale helper — elevates write calls only. Reads never need privilege.
#----------------------------------------------------------------------
_need_sudo=0
if [[ $EUID -ne 0 ]]; then
    _op="$(tailscale debug prefs 2>/dev/null | grep -oiE '"OperatorUser":\s*"[^"]*"' || true)"
    [[ "$_op" == *"\"$USER\""* ]] || _need_sudo=1
fi
TS() {  # elevate write ops if this user is not the tailscale operator
    if (( _need_sudo )); then sudo tailscale "$@"; else tailscale "$@"; fi
}

MODE="${1:-apply}"

#----------------------------------------------------------------------
# 1) Preflight: tailscale present, backend, and MagicDNS name
#----------------------------------------------------------------------
echo "\n<<< Tailscale Serve map for this host >>>\n"

command -v tailscale >/dev/null 2>&1 || { echo "ERROR: tailscale not installed."; exit 1; }
tailscale status >/dev/null 2>&1   || { echo "ERROR: tailscaled not running / not logged in (try: sudo tailscale up)."; exit 1; }

FQDN="$(tailscale status --json 2>/dev/null | grep -oE '"DNSName":\s*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)\."/\1/')"
echo "1) This host on the tailnet: ${FQDN:-<unknown>}"
echo "   Reminder: HTTPS needs the tailnet's 'HTTPS Certificates' feature ON"
echo "   (admin console → Settings → Features). First hit provisions a cert (~a few s)."

#----------------------------------------------------------------------
# 2) status / reset shortcuts
#----------------------------------------------------------------------
if [[ "$MODE" == "status" ]]; then
    echo "\n2) Current serve status:\n"
    tailscale serve status || echo "   (no serve config)"
    exit 0
fi

if [[ "$MODE" == "reset" ]]; then
    echo "\n2) Tearing down every port in SERVE_MAP..."
    for port in "${(k)SERVE_MAP[@]}"; do
        echo "   - https:$port off"
        TS serve --https "$port" off 2>/dev/null || true
    done
    echo "\n   Remaining serve config:"; tailscale serve status || echo "   (none)"
    exit 0
fi

#----------------------------------------------------------------------
# 3) Port-safety guard — never clash with AdGuard (host :53/:80/:443/:3000)
#----------------------------------------------------------------------
echo "\n3) Port-safety check (AdGuard coexistence)..."
# Snapshot host listeners so we can warn on a collision.
LISTEN="$(ss -tlnH 2>/dev/null | awk '{print $4}')"

for port in "${(k)SERVE_MAP[@]}"; do
    # 80 and 443 belong to AdGuard.
    if [[ "$port" == "80" || "$port" == "443" ]]; then
        echo "   ERROR: refusing serve port $port — AdGuard holds host :80/:443."
        echo "          Pick an 8000–9999 port instead."
        exit 1
    fi
    # Something else already holds this port.
    if print -r -- "$LISTEN" | grep -qE "[:.]$port\$"; then
        echo "   WARNING: host already has a listener on :$port — verify it's this"
        echo "            serve and not another service before continuing."
    fi
done
echo "   OK — serve binds only on the tailscale interface; AdGuard's"
echo "   :53 (DNS), :80, :3000 (UI) are never touched by these mappings."

#----------------------------------------------------------------------
# 4) Apply the map — re-running overwrites each handler
#----------------------------------------------------------------------
echo "\n4) Applying serve map..."
for port in "${(k)SERVE_MAP[@]}"; do
    backend="${SERVE_MAP[$port]}"
    echo "   - https://${FQDN:-<host>}:$port  ->  $backend"
    if ! TS serve --bg --https "$port" "$backend"; then
        echo "     ERROR applying :$port. If it says 'access denied', run once:"
        echo "       sudo tailscale set --operator=\$USER   (then re-run this script)"
        exit 1
    fi
done

#----------------------------------------------------------------------
# 5) Show the result
#----------------------------------------------------------------------
echo "\n5) Live serve status:\n"
tailscale serve status

echo "\n<<< Done >>>"
echo "Open from any of YOUR tailnet devices (MagicDNS on):"
for port in "${(k)SERVE_MAP[@]}"; do
    echo "  https://${FQDN:-<host>}:$port   -> ${SERVE_MAP[$port]}"
done
echo "\nThis config persists across reboots (stored in tailscaled state)."
echo "Revert everything with:  ./setup_tailscale_serve.zsh reset"
