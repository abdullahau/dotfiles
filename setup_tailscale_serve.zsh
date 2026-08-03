#!/usr/bin/env zsh
#
# setup_tailscale_serve.zsh — zsh, self-contained. Copy this ONE file anywhere
# and run it. Declares (and re-applies) the Tailscale Serve map for this host.
#
# WHAT: Exposes LAN-only admin pages that CANNOT run Tailscale themselves (the
# D-Link main router at 192.168.0.1) onto the tailnet over HTTPS, reachable at
#   https://<this-host>.<tailnet>.ts.net:<port>
# from any of your devices — no subnet routing required.
#
# WHY a script: `tailscale serve` config is stored per-node and is NOT visible
# or editable from the admin console (login.tailscale.com). `tailscale serve
# status` on the box is the only source of truth. This file is that source of
# truth in version control: it documents the intended map, re-applies it
# idempotently after a rebuild, and guards against port clashes with AdGuard.
#
# SERVE vs SUBNET: Serve is a per-node TLS reverse proxy to a backend. It binds
# ONLY on the tailscale interface (e.g. 100.x:8443) and merely dials OUT to the
# backend — it never binds host :80/:443. That is what keeps it clear of AdGuard
# (see the port-safety check in section 3).
#
# Idempotent and safe to re-run.
#
# Usage:
#   ./setup_tailscale_serve.zsh            # apply the SERVE_MAP below
#   ./setup_tailscale_serve.zsh status     # just print current serve status
#   ./setup_tailscale_serve.zsh reset      # tear DOWN everything in SERVE_MAP
#
# One-time convenience so this never needs sudo again (grants your user the
# right to drive tailscale, including serve + cert):
#   sudo tailscale set --operator=$USER
#
# -----------------------------------------------------------------------------
# EDIT HERE: the desired map of  <tailnet-https-port>  ->  <local backend URL>
# -----------------------------------------------------------------------------
# Add a line per admin page. Pick ports in the 8000–9999 range; NEVER 80 or 443
# (AdGuard, host-networked, already holds those — the script refuses them).
# The extender is intentionally NOT served: it is a mesh/AP node with no IPv4
# (IPv6 link-local only) and is managed from the main router's mesh UI instead.
#
typeset -A SERVE_MAP=(
    8443  "http://192.168.0.1:80"      # D-Link DIR-853 main router admin
    # 8081  "http://localhost:3000"    # (example) AdGuard Home UI — enable if wanted
)

setopt nounset pipefail        # NOT errexit: we handle tailscale errors explicitly

#----------------------------------------------------------------------
# tailscale helper — auto-elevates only the MUTATING calls when needed.
# Reads (`serve status`) never need privilege; writes do, unless
# `--operator=$USER` has been set once (see header).
#----------------------------------------------------------------------
_need_sudo=0
if [[ $EUID -ne 0 ]]; then
    _op="$(tailscale debug prefs 2>/dev/null | grep -oiE '"OperatorUser":\s*"[^"]*"' || true)"
    [[ "$_op" == *"\"$USER\""* ]] || _need_sudo=1
fi
TS() {  # TS <tailscale args...>  — elevate write ops if this user isn't the operator
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
# Snapshot what is already LISTENing on the host, so we can warn on collisions.
LISTEN="$(ss -tlnH 2>/dev/null | awk '{print $4}')"

for port in "${(k)SERVE_MAP[@]}"; do
    # Hard rule: 80/443 belong to AdGuard (host-networked). Serve must not take them.
    if [[ "$port" == "80" || "$port" == "443" ]]; then
        echo "   ERROR: refusing serve port $port — AdGuard holds host :80/:443."
        echo "          Pick an 8000–9999 port instead."
        exit 1
    fi
    # Soft warn: something ELSE already bound this exact port on the host.
    if print -r -- "$LISTEN" | grep -qE "[:.]$port\$"; then
        echo "   WARNING: host already has a listener on :$port — verify it's this"
        echo "            serve and not another service before continuing."
    fi
done
echo "   OK — serve binds only on the tailscale interface; AdGuard's"
echo "   :53 (DNS), :80, :3000 (UI) are never touched by these mappings."

#----------------------------------------------------------------------
# 4) Apply the map (declarative: re-running overwrites each handler)
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
