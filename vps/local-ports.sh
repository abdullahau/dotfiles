#!/usr/bin/env bash
#
# Opens public TCP/UDP ports for a service running on THIS VPS itself (e.g.
# a web app bound to :8080 locally). Not a relay: no DNAT, no Tailscale —
# just punches a hole in the VPS's own firewall (iptables INPUT + ufw).
#
# For forwarding to a service on ANOTHER tailnet host, use relay.sh instead.
#
# Usage: ./local-ports.sh   (no args — reads .env next to this script)
#   LOCAL_PORTS=8080   # comma list of PORT | PORT/udp | PORT/tcp+udp. Empty = no-op.
#
# Re-run after editing LOCAL_PORTS: opens new entries, closes dropped ones.
# Safe to re-run any time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

LOCAL_PORTS="${LOCAL_PORTS:-}"

# LOCAL_PORTS -> normalized "PORT PROTO" lines. Duplicated (not sourced) in
# the apply script below so that script stays self-contained.
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
    exit 0
fi

if ! normalize_local_ports "$LOCAL_PORTS" > /dev/null; then
    exit 1
fi

printf '\n<<< Starting VPS Local Ports Setup (LOCAL_PORTS=%s) >>>\n\n' "$LOCAL_PORTS"

#----------------------------------------------------------------------
# 1) Open local ports
#----------------------------------------------------------------------

printf '1) Reconciling locally-opened ports (LOCAL_PORTS=%s)...\n\n' "$LOCAL_PORTS"

# Rule logic lives in a standalone script so "set up now" and "restore on
# every boot" (systemd unit, below) run identical logic.
sudo tee /usr/local/sbin/vps-local-ports-apply.sh > /dev/null << 'APPLY_EOF'
#!/usr/bin/env bash
# Managed by local-ports.sh — do not edit by hand.
# Reconciles iptables INPUT ACCEPT rules against LOCAL_PORTS: opens what's
# desired, closes what's no longer listed. State tracked in STATE_FILE.
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
    echo "  close: local ${port}/${proto}  (also remove its OCI ingress rule)"
}

DESIRED_FILE="$(mktemp)"
trap 'rm -f "$DESIRED_FILE"' EXIT
normalize_local_ports "$LOCAL_PORTS" > "$DESIRED_FILE"

while read -r port proto; do
    [[ -z "${port:-}" ]] && continue
    if ! grep -qxF "$port $proto" "$DESIRED_FILE"; then
        close_port "$port" "$proto"
    fi
done < "$STATE_FILE"

while read -r port proto; do
    [[ -z "${port:-}" ]] && continue
    open_port "$port" "$proto"
done < "$DESIRED_FILE"

cp "$DESIRED_FILE" "$STATE_FILE"
APPLY_EOF
sudo chmod +x /usr/local/sbin/vps-local-ports-apply.sh

sudo LOCAL_PORTS="$LOCAL_PORTS" /usr/local/sbin/vps-local-ports-apply.sh

printf '\n1.a) Persisting across reboots...\n\n'

# iptables-persistent: fast restore, but can be an empty/stale snapshot.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# vps-local-ports.service: the actual guarantee — re-applies rules on every boot.
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
# 2) Manual step reminder — Oracle's cloud firewall is separate from iptables
#----------------------------------------------------------------------

printf '\n<<< VPS Local Ports Setup Complete >>>\n\n'
echo "ACTION REQUIRED: open each port below in the OCI console (separate from"
echo "iptables/ufw — Oracle blocks it at the cloud level regardless):"
echo "  Console -> Compute -> Instances -> (this instance) -> attached VNIC"
echo "  -> Subnet -> Default Security List -> Ingress Rules -> Add Ingress Rule"
echo "  (Source CIDR 0.0.0.0/0, IP Protocol TCP or UDP, Destination Port <port>)."
echo ""
echo "Ports that must be OPEN in OCI right now:"
normalize_local_ports "$LOCAL_PORTS" | while read -r port proto; do
    echo "  - ${port}/${proto}"
done
echo ""
echo "Removed a port from LOCAL_PORTS? Its VPS-side rules are closed above —"
echo "also delete its OCI ingress rule; this script can't reach OCI's API."
