#!/usr/bin/env bash
#
# Self-contained, pure bash. Copy this ONE file to a VPS and run it.
#
# Opens public TCP/UDP ports for a service running ON THIS VPS ITSELF (e.g. a
# web app bound to :8080 locally). This is NOT a relay: no DNAT, no
# MASQUERADE, no Tailscale — traffic terminates right here, so all this does
# is punch a hole in the VPS's own firewall (iptables INPUT + ufw if active).
#
# For forwarding a port through to a service on ANOTHER tailnet host (e.g.
# Plex on the home server), use setup_vps_relay.sh instead.
#
# Usage:
#   ./setup_vps_local_ports.sh
#
# No args — LOCAL_PORTS comes from .env next to this script (same convention
# as setup_vps_relay.sh's TARGET_IP/RELAY_PORTS):
#
#   LOCAL_PORTS=8080                 # required — nothing to do if unset/empty
#
# LOCAL_PORTS is a comma-separated list of entries:
#   PORT              TCP
#   PORT/udp          UDP instead of TCP
#   PORT/tcp+udp      both protocols
#
# Example .env:
#   LOCAL_PORTS=8080,3000/tcp+udp,51820/udp
#
# Closing a port later is just editing LOCAL_PORTS and re-running: any port
# that was opened before but is no longer listed gets its rule removed.
#
# Safe to re-run: every iptables rule is checked with `-C` before it's added
# or removed.
#
# Reboot persistence uses TWO independent mechanisms, same as setup_vps_relay.sh:
#   1. iptables-persistent      — restores the saved ruleset snapshot at boot.
#   2. vps-local-ports.service  — a systemd oneshot that RE-APPLIES the rules
#                                  on every boot, so it survives even if the
#                                  snapshot is empty/flushed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

LOCAL_PORTS="${LOCAL_PORTS:-}"

# Turns a LOCAL_PORTS string into normalized "PORT PROTO" lines (one per
# protocol), validating as it goes. Duplicated (not sourced) inside the
# generated apply script below so that script stays a single self-contained
# file that works identically at setup time and on every future boot.
normalize_local_ports() {
    local raw="$1" entry portspec proto port
    IFS=',' read -ra _entries <<< "$raw"
    for entry in "${_entries[@]}"; do
        entry="$(echo -n "$entry" | tr -d '[:space:]')"
        [[ -z "$entry" ]] && continue
        proto="tcp"
        portspec="$entry"
        if [[ "$entry" == */* ]]; then
            portspec="${entry%%/*}"
            proto="${entry##*/}"
        fi
        port="$portspec"
        if ! [[ "$port" =~ ^[0-9]{1,5}$ ]]; then
            echo "ERROR: invalid port in LOCAL_PORTS entry '$entry' (expected NUMBER)" >&2
            return 1
        fi
        if (( port < 1 || port > 65535 )); then
            echo "ERROR: port out of range (1-65535) in LOCAL_PORTS entry '$entry'" >&2
            return 1
        fi
        case "$proto" in
            tcp) echo "$port tcp" ;;
            udp) echo "$port udp" ;;
            tcp+udp|both) echo "$port tcp"; echo "$port udp" ;;
            *)
                echo "ERROR: invalid protocol '$proto' in LOCAL_PORTS entry '$entry' (expected tcp, udp, or tcp+udp)" >&2
                return 1
                ;;
        esac
    done
}

if [[ -z "$LOCAL_PORTS" ]]; then
    echo "LOCAL_PORTS is not set (or empty) in .env — nothing to open. Exiting."
    echo "  Set e.g. LOCAL_PORTS=8080,3000/tcp+udp in .env next to this script and re-run."
    exit 0
fi

# Fail fast on a bad LOCAL_PORTS before touching anything.
if ! normalize_local_ports "$LOCAL_PORTS" > /dev/null; then
    exit 1
fi

printf '\n<<< Starting VPS Local Ports Setup (LOCAL_PORTS=%s) >>>\n\n' "$LOCAL_PORTS"

#----------------------------------------------------------------------
# 1) Open local ports
#----------------------------------------------------------------------

printf '1) Reconciling locally-opened ports (LOCAL_PORTS=%s)...\n\n' "$LOCAL_PORTS"

# Same split as setup_vps_relay.sh: the rule logic lives in a standalone apply
# script installed to /usr/local/sbin so the "set up now" path and the
# "restore on every boot" path (systemd service, below) run the EXACT same
# idempotent logic — no drift. It reads LOCAL_PORTS from the environment.
sudo tee /usr/local/sbin/vps-local-ports-apply.sh > /dev/null << 'APPLY_EOF'
#!/usr/bin/env bash
# Managed by setup_vps_local_ports.sh — do not edit by hand.
# Idempotently (re-)applies iptables INPUT ACCEPT + ufw allow rules for every
# entry in LOCAL_PORTS, and CLOSES (removes) rules for any port that was
# opened before but has since been dropped from LOCAL_PORTS. State (what's
# currently open) lives in STATE_FILE so this script knows what to close. Run
# once at setup and again on every boot via vps-local-ports.service.
set -euo pipefail

: "${LOCAL_PORTS:=}"

STATE_FILE=/etc/vps-relay/local-ports.conf
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

normalize_local_ports() {
    local raw="$1" entry portspec proto port
    IFS=',' read -ra _entries <<< "$raw"
    for entry in "${_entries[@]}"; do
        entry="$(echo -n "$entry" | tr -d '[:space:]')"
        [[ -z "$entry" ]] && continue
        proto="tcp"
        portspec="$entry"
        if [[ "$entry" == */* ]]; then
            portspec="${entry%%/*}"
            proto="${entry##*/}"
        fi
        port="$portspec"
        if ! [[ "$port" =~ ^[0-9]{1,5}$ ]]; then
            echo "ERROR: invalid port in LOCAL_PORTS entry '$entry'" >&2
            return 1
        fi
        case "$proto" in
            tcp) echo "$port tcp" ;;
            udp) echo "$port udp" ;;
            tcp+udp|both) echo "$port tcp"; echo "$port udp" ;;
            *) echo "ERROR: invalid protocol '$proto' in LOCAL_PORTS entry '$entry'" >&2; return 1 ;;
        esac
    done
}

add_input_rule_if_missing() {
    local port="$1" proto="$2"
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
        || iptables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT
}
remove_input_rule_if_present() {
    local port="$1" proto="$2"
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
        && iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT || true
}
ufw_active() {
    command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"
}

open_port() {
    local port="$1" proto="$2"
    add_input_rule_if_missing "$port" "$proto"
    if ufw_active; then
        ufw allow "${port}/${proto}" comment "vps-local-ports" >/dev/null 2>&1 || true
    fi
    echo "  open:  local ${port}/${proto}"
}

close_port() {
    local port="$1" proto="$2"
    remove_input_rule_if_present "$port" "$proto"
    if ufw_active; then
        ufw delete allow "${port}/${proto}" >/dev/null 2>&1 || true
    fi
    echo "  close: local ${port}/${proto}  (removed from LOCAL_PORTS — also remove its OCI ingress rule)"
}

DESIRED_FILE="$(mktemp)"
trap 'rm -f "$DESIRED_FILE"' EXIT
normalize_local_ports "$LOCAL_PORTS" > "$DESIRED_FILE"

# Close ports that were open before but are no longer in LOCAL_PORTS.
while read -r port proto; do
    [[ -z "${port:-}" ]] && continue
    if ! grep -qxF "$port $proto" "$DESIRED_FILE"; then
        close_port "$port" "$proto"
    fi
done < "$STATE_FILE"

# Open everything currently desired (idempotent no-op for what's already open).
while read -r port proto; do
    [[ -z "${port:-}" ]] && continue
    open_port "$port" "$proto"
done < "$DESIRED_FILE"

cp "$DESIRED_FILE" "$STATE_FILE"
APPLY_EOF
sudo chmod +x /usr/local/sbin/vps-local-ports-apply.sh

# Apply the rules right now.
sudo LOCAL_PORTS="$LOCAL_PORTS" /usr/local/sbin/vps-local-ports-apply.sh

printf '\n1.a) Persisting across reboots (two independent mechanisms)...\n\n'

# Mechanism 1 — iptables-persistent: saves the current ruleset and restores it
# early at boot. Shared with setup_vps_relay.sh if that's also installed on
# this box; harmless/no-op to install again if it's already present.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Mechanism 2 — vps-local-ports.service: the actual guarantee. A oneshot
# systemd unit that RE-APPLIES the rules on every boot. Idempotent (-C checks
# + state-file reconcile), so it never stacks duplicates and closes anything
# dropped from LOCAL_PORTS since the last run.
sudo tee /etc/systemd/system/vps-local-ports.service > /dev/null << EOF
[Unit]
Description=VPS local port exposure (LOCAL_PORTS=$LOCAL_PORTS)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=LOCAL_PORTS=$LOCAL_PORTS
ExecStart=/usr/local/sbin/vps-local-ports-apply.sh

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable vps-local-ports.service

#----------------------------------------------------------------------
# 2) Manual step reminder — cannot be scripted without OCI credentials
#----------------------------------------------------------------------

printf '\n<<< VPS Local Ports Setup Complete >>>\n\n'
echo "ACTION REQUIRED: Oracle blocks traffic at the cloud level regardless of"
echo "iptables/ufw. This is a SECOND, separate firewall — both must allow a"
echo "port or the service won't be reachable. One-time per port, in the OCI"
echo "console:"
echo "  Console -> Compute -> Instances -> (this instance) -> attached VNIC"
echo "  -> Subnet -> Default Security List -> Ingress Rules -> Add Ingress Rule"
echo "  (Source CIDR 0.0.0.0/0, IP Protocol TCP or UDP, Destination Port <port>)."
echo ""
echo "Ports that must be OPEN in OCI right now:"
normalize_local_ports "$LOCAL_PORTS" | while read -r port proto; do
    echo "  - ${port}/${proto}"
done
echo ""
echo "If you just removed a port from LOCAL_PORTS, its rules were closed on"
echo "this VPS above — also DELETE its OCI ingress rule the same way; this"
echo "script cannot reach OCI's API."
