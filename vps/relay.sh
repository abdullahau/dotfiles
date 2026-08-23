#!/usr/bin/env bash
#
# DNATs public TCP/UDP ports on this VPS to a service on another Tailscale
# node (e.g. Plex on the home server). For a service running on this VPS
# itself, use local-ports.sh instead.
#
# Usage: ./relay.sh   (no args — reads .env next to this script)
#   TARGET_IP=100.125.140.11   # required: tailnet IP of the node running the service
#   RELAY_PORTS=32400          # default: 32400. Comma list of:
#                               #   PORT | PUBLIC:TARGET | PORT/udp | PORT/tcp+udp
#
# Re-run after editing RELAY_PORTS: opens new entries, closes dropped ones.
# Safe to re-run any time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

RELAY_PORTS="${RELAY_PORTS:-32400}"

if [[ -z "${TARGET_IP:-}" ]]; then
    echo "ERROR: TARGET_IP is not set. Put TARGET_IP=<tailnet IP> in .env next to this script."
    exit 1
fi

if [[ ! "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: TARGET_IP '$TARGET_IP' is not a valid IPv4 address."
    exit 1
fi

# RELAY_PORTS -> normalized "PUBLIC TARGET PROTO" lines. Duplicated (not
# sourced) in the apply script below so that script stays self-contained.
normalize_relay_ports() {
    local raw="$1" entry portspec proto pub tgt
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
        pub="$portspec"; tgt="$portspec"
        if [[ "$portspec" == *:* ]]; then
            pub="${portspec%%:*}"
            tgt="${portspec##*:}"
        fi
        if ! [[ "$pub" =~ ^[0-9]{1,5}$ && "$tgt" =~ ^[0-9]{1,5}$ ]]; then
            echo "ERROR: invalid port in RELAY_PORTS entry '$entry' (expected NUMBER or NUMBER:NUMBER)" >&2
            return 1
        fi
        if (( pub < 1 || pub > 65535 || tgt < 1 || tgt > 65535 )); then
            echo "ERROR: port out of range (1-65535) in RELAY_PORTS entry '$entry'" >&2
            return 1
        fi
        case "$proto" in
            tcp) echo "$pub $tgt tcp" ;;
            udp) echo "$pub $tgt udp" ;;
            tcp+udp|both) echo "$pub $tgt tcp"; echo "$pub $tgt udp" ;;
            *)
                echo "ERROR: invalid protocol '$proto' in RELAY_PORTS entry '$entry' (expected tcp, udp, or tcp+udp)" >&2
                return 1
                ;;
        esac
    done
}

if ! normalize_relay_ports "$RELAY_PORTS" > /dev/null; then
    exit 1
fi

printf '\n<<< Starting VPS Relay Setup (RELAY_PORTS=%s -> %s) >>>\n\n' "$RELAY_PORTS" "$TARGET_IP"

#----------------------------------------------------------------------
# 1) Ensure Tailscale is installed, running, and joined to the tailnet
#----------------------------------------------------------------------

printf '\n1) Ensuring Tailscale is installed and up...\n\n'

# Wait for any apt/dpkg lock held by unattended-upgrades on a fresh VM.
if command -v fuser >/dev/null 2>&1; then
    printed=0
    for _ in $(seq 1 60); do
        if ! sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
                        /var/cache/apt/archives/lock /var/lib/apt/lists/lock \
                        >/dev/null 2>&1; then
            break
        fi
        if [[ $printed -eq 0 ]]; then
            echo "  waiting for apt/dpkg lock to release (unattended-upgrades?)..."
            printed=1
        fi
        sleep 2
    done
fi

sudo dpkg --configure -a || true

if ! command -v tailscale >/dev/null 2>&1; then
    echo "tailscale not found — installing via the official script..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled || true
for _ in $(seq 1 20); do
    if ! tailscale status 2>&1 | grep -qi 'failed to connect to local tailscaled'; then
        break
    fi
    sleep 1
done

if ! tailscale status >/dev/null 2>&1; then
    # A relay must not advertise as exit node/subnet router — plain membership only.
    if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
        echo "Joining the tailnet with TAILSCALE_AUTH_KEY from .env..."
        sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --accept-dns=false
    else
        echo "ERROR: tailscale is not up and TAILSCALE_AUTH_KEY is unset (missing .env?)."
        echo "       Run manually: sudo tailscale up"
        exit 1
    fi
fi

echo "This VPS's tailnet IP (for reference, not used below):"
tailscale ip -4 2>/dev/null || echo "  (unavailable)"

#----------------------------------------------------------------------
# 1.a) Keep DNS resolution local to this VPS
#----------------------------------------------------------------------

printf '\n1.a) Pointing DNS at the local/cloud resolver instead of the tailnet...\n\n'

# A tailnet DNS override (e.g. home AdGuard) adds huge per-lookup latency on
# a VPS, breaks ad-blocked domains as "connection refused", and geo-resolves
# CDNs to the wrong region. Full tailnet membership is kept — only DNS opts
# out. Override: VPS_ACCEPT_DNS=true ./relay.sh
if [[ "${VPS_ACCEPT_DNS:-false}" == "true" ]]; then
    echo "  VPS_ACCEPT_DNS=true — leaving Tailscale DNS enabled (not recommended for a VPS)."
else
    sudo tailscale set --accept-dns=false || true
    echo "  tailscale --accept-dns=false (persists across reboots)"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved; then
    sudo systemctl restart systemd-resolved
    sleep 2
fi

if getent hosts example.com >/dev/null 2>&1; then
    echo "  DNS OK — resolving without the tailnet nameserver."
else
    echo "  WARNING: DNS is NOT resolving after this change!"
    echo "           Inspect: resolvectl status ; cat /etc/resolv.conf"
    echo "           Check /etc/systemd/resolved.conf.d/ for a stale drop-in."
    echo "           Revert with: sudo tailscale set --accept-dns=true"
fi

#----------------------------------------------------------------------
# 2) Enable IPv4 + IPv6 forwarding
#----------------------------------------------------------------------

printf '\n2) Enabling IPv4 + IPv6 forwarding...\n\n'

sudo tee /etc/sysctl.d/99-vps-relay.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-vps-relay.conf > /dev/null

#----------------------------------------------------------------------
# 3) Forward public ports -> target over the tailnet
#----------------------------------------------------------------------

printf '\n3) Reconciling relayed ports (RELAY_PORTS=%s -> %s)...\n\n' "$RELAY_PORTS" "$TARGET_IP"

# Rule logic lives in a standalone script so "set up now" and "restore on
# every boot" (systemd unit, 3.a) run identical logic.
sudo tee /usr/local/sbin/vps-relay-apply.sh > /dev/null << 'APPLY_EOF'
#!/usr/bin/env bash
# Managed by relay.sh — do not edit by hand.
# Reconciles iptables DNAT rules against RELAY_PORTS: opens what's desired,
# closes what's no longer listed. State tracked in STATE_FILE.
set -euo pipefail

: "${TARGET_IP:?TARGET_IP not set}"
: "${RELAY_PORTS:=32400}"

STATE_FILE=/etc/vps-relay/ports.conf
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

PUB_IF="$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')"

sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null

normalize_relay_ports() {
    local raw="$1" entry portspec proto pub tgt
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
        pub="$portspec"; tgt="$portspec"
        if [[ "$portspec" == *:* ]]; then
            pub="${portspec%%:*}"
            tgt="${portspec##*:}"
        fi
        if ! [[ "$pub" =~ ^[0-9]{1,5}$ && "$tgt" =~ ^[0-9]{1,5}$ ]]; then
            echo "ERROR: invalid port in RELAY_PORTS entry '$entry'" >&2
            return 1
        fi
        case "$proto" in
            tcp) echo "$pub $tgt tcp" ;;
            udp) echo "$pub $tgt udp" ;;
            tcp+udp|both) echo "$pub $tgt tcp"; echo "$pub $tgt udp" ;;
            *) echo "ERROR: invalid protocol '$proto' in RELAY_PORTS entry '$entry'" >&2; return 1 ;;
        esac
    done
}

add_nat_rule_if_missing() {
    local chain="$1"; shift
    iptables -t nat -C "$chain" "$@" 2>/dev/null || iptables -t nat -A "$chain" "$@"
}
remove_nat_rule_if_present() {
    local chain="$1"; shift
    iptables -t nat -C "$chain" "$@" 2>/dev/null && iptables -t nat -D "$chain" "$@" || true
}
add_forward_rule_if_missing() {
    iptables -C FORWARD "$@" -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 "$@" -j ACCEPT
}
remove_forward_rule_if_present() {
    iptables -C FORWARD "$@" -j ACCEPT 2>/dev/null && iptables -D FORWARD "$@" -j ACCEPT || true
}
ufw_active() {
    command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"
}

open_port() {
    local pub="$1" tgt="$2" proto="$3"
    add_nat_rule_if_missing PREROUTING -i "$PUB_IF" -p "$proto" --dport "$pub" \
        -j DNAT --to-destination "${TARGET_IP}:${tgt}"
    add_nat_rule_if_missing POSTROUTING -d "$TARGET_IP" -p "$proto" --dport "$tgt" \
        -j MASQUERADE
    add_forward_rule_if_missing -p "$proto" -d "$TARGET_IP" --dport "$tgt"
    if ufw_active; then
        ufw allow "${pub}/${proto}" comment "vps-relay" >/dev/null 2>&1 || true
        ufw route allow proto "$proto" to "$TARGET_IP" port "$tgt" >/dev/null 2>&1 || true
    fi
    echo "  open:  public ${pub}/${proto} -> ${TARGET_IP}:${tgt}"
}

close_port() {
    local pub="$1" tgt="$2" proto="$3"
    remove_nat_rule_if_present PREROUTING -i "$PUB_IF" -p "$proto" --dport "$pub" \
        -j DNAT --to-destination "${TARGET_IP}:${tgt}"
    remove_nat_rule_if_present POSTROUTING -d "$TARGET_IP" -p "$proto" --dport "$tgt" \
        -j MASQUERADE
    remove_forward_rule_if_present -p "$proto" -d "$TARGET_IP" --dport "$tgt"
    if ufw_active; then
        ufw delete allow "${pub}/${proto}" >/dev/null 2>&1 || true
        ufw route delete allow proto "$proto" to "$TARGET_IP" port "$tgt" >/dev/null 2>&1 || true
    fi
    echo "  close: public ${pub}/${proto} -x-> ${TARGET_IP}:${tgt}  (also remove its OCI ingress rule)"
}

DESIRED_FILE="$(mktemp)"
trap 'rm -f "$DESIRED_FILE"' EXIT
normalize_relay_ports "$RELAY_PORTS" > "$DESIRED_FILE"

while read -r pub tgt proto; do
    [[ -z "${pub:-}" ]] && continue
    if ! grep -qxF "$pub $tgt $proto" "$DESIRED_FILE"; then
        close_port "$pub" "$tgt" "$proto"
    fi
done < "$STATE_FILE"

while read -r pub tgt proto; do
    [[ -z "${pub:-}" ]] && continue
    open_port "$pub" "$tgt" "$proto"
done < "$DESIRED_FILE"

cp "$DESIRED_FILE" "$STATE_FILE"
APPLY_EOF
sudo chmod +x /usr/local/sbin/vps-relay-apply.sh

sudo TARGET_IP="$TARGET_IP" RELAY_PORTS="$RELAY_PORTS" \
    /usr/local/sbin/vps-relay-apply.sh

printf '\n3.a) Persisting across reboots...\n\n'

# iptables-persistent: fast restore, but can be an empty/stale snapshot.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# vps-relay.service: the actual guarantee — re-applies rules on every boot.
sudo tee /etc/systemd/system/vps-relay.service > /dev/null << EOF
[Unit]
Description=VPS tailnet relay (RELAY_PORTS=$RELAY_PORTS -> $TARGET_IP)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=TARGET_IP=$TARGET_IP
Environment=RELAY_PORTS=$RELAY_PORTS
ExecStart=/usr/local/sbin/vps-relay-apply.sh

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable vps-relay.service

#----------------------------------------------------------------------
# 4) Manual step reminder — Oracle's cloud firewall is separate from iptables
#----------------------------------------------------------------------

printf '\n<<< VPS Relay Setup Complete >>>\n\n'
echo "ACTION REQUIRED: open each port below in the OCI console (separate from"
echo "iptables/ufw — Oracle blocks it at the cloud level regardless):"
echo "  Console -> Compute -> Instances -> (this instance) -> attached VNIC"
echo "  -> Subnet -> Default Security List -> Ingress Rules -> Add Ingress Rule"
echo "  (Source CIDR 0.0.0.0/0, IP Protocol TCP or UDP, Destination Port <port>)."
echo ""
echo "Ports that must be OPEN in OCI right now:"
normalize_relay_ports "$RELAY_PORTS" | while read -r pub _tgt proto; do
    echo "  - ${pub}/${proto}"
done
echo ""
echo "Removed a port from RELAY_PORTS? Its VPS-side rules are closed above —"
echo "also delete its OCI ingress rule; this script can't reach OCI's API."
