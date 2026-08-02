#!/usr/bin/env bash
#
# Self-contained port of setup_vps_relay.zsh — pure bash, no zsh, no .env, no
# brew, no dotfiles bootstrap. Copy this ONE file to a VPS and run it.
#
# Turns a public VPS into a tailnet relay: DNATs one public TCP port through to
# a service on another tailnet node (e.g. Plex on the home server, reached over
# Tailscale instead of exposing the home connection). Assumes the VPS is
# ALREADY joined to the tailnet (it does NOT install or 'tailscale up' for you).
#
# Usage:
#   ./setup_vps_relay.sh <target-tailnet-ip> [port] [public-port]
#
# Example (Plex, same port in and out):
#   ./setup_vps_relay.sh 100.125.140.11 32400
#
# Safe to re-run: every iptables rule is checked with `-C` before it's added,
# and the sysctl drop-in is written fresh each time.
#
# Reboot persistence uses TWO independent mechanisms (see section 3.a):
#   1. iptables-persistent  — restores the saved ruleset snapshot at boot.
#   2. vps-relay.service    — a systemd oneshot that RE-APPLIES the rules on
#                             every boot (after tailscaled), so the relay
#                             survives even if the snapshot is empty/flushed.

set -euo pipefail

# Self-contained, but reads TAILSCALE_AUTH_KEY from a .env sitting next to this
# script (same convention as setup_ubuntu.zsh) if present.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

TARGET_IP="${1:-}"
TARGET_PORT="${2:-32400}"
PUBLIC_PORT="${3:-$TARGET_PORT}"

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-tailnet-ip> [port=32400] [public-port=<port>]"
    echo "  target-tailnet-ip  Tailscale IP of the node actually running the service"
    echo "                     (e.g. the home server's 'tailscale ip -4', NOT this VPS's)."
    exit 1
fi

printf '\n<<< Starting VPS Relay Setup (public:%s -> %s:%s) >>>\n\n' \
    "$PUBLIC_PORT" "$TARGET_IP" "$TARGET_PORT"

#----------------------------------------------------------------------
# 1) Require the tailnet (self-sufficient: we do NOT install or join for you)
#----------------------------------------------------------------------

printf '\n1) Ensuring Tailscale is installed and up...\n\n'

if ! command -v tailscale >/dev/null 2>&1; then
    echo "tailscale not found — installing via the official script..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale status >/dev/null 2>&1; then
    # A relay must NOT advertise itself as an exit node or subnet router; it
    # only needs plain tailnet membership so the DNAT target is reachable.
    if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
        echo "Joining the tailnet with TAILSCALE_AUTH_KEY from .env..."
        sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}"
    else
        echo "ERROR: tailscale is not up and TAILSCALE_AUTH_KEY is unset (missing .env?)."
        echo "       Put TAILSCALE_AUTH_KEY=... in a .env next to this script, or run:"
        echo "         sudo tailscale up"
        exit 1
    fi
fi

echo "This VPS's tailnet IP (for reference, not used below):"
tailscale ip -4 2>/dev/null || echo "  (unavailable)"

#----------------------------------------------------------------------
# 2) Enable IPv4 forwarding
#----------------------------------------------------------------------

printf '\n2) Enabling IPv4 + IPv6 forwarding...\n\n'

# Enable BOTH families, matching setup_ubuntu.zsh's 99-tailscale.conf. IPv6
# forwarding in particular is what clears the Tailscale health warning
# "Subnet routing is enabled, but IP forwarding is disabled" whenever the node
# advertises any IPv6 route (e.g. an exit node's ::/0). Applied with `sysctl -p
# <file>` (not --system) so unrelated cloud-image keys don't spam warnings.
sudo tee /etc/sysctl.d/99-vps-relay.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-vps-relay.conf > /dev/null

#----------------------------------------------------------------------
# 3) Forward public port -> target over the tailnet
#----------------------------------------------------------------------

printf '\n3) Forwarding public :%s -> %s:%s over the tailnet...\n\n' \
    "$PUBLIC_PORT" "$TARGET_IP" "$TARGET_PORT"

PUB_IF="$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')"
echo "Detected public interface: $PUB_IF"

# The rule logic lives in a standalone apply script installed to
# /usr/local/sbin so the "set up now" path and the "restore on every boot"
# path (systemd service, 3.a) run the EXACT same idempotent logic — no drift.
# It reads TARGET_IP/TARGET_PORT/PUBLIC_PORT from the environment and detects
# the public interface itself, so it needs no arguments at boot.
sudo tee /usr/local/sbin/vps-relay-apply.sh > /dev/null << 'APPLY_EOF'
#!/usr/bin/env bash
# Managed by setup_vps_relay.sh — do not edit by hand.
# Idempotently (re-)applies the tailnet relay iptables rules. Run once at
# setup and again on every boot via vps-relay.service.
set -euo pipefail

: "${TARGET_IP:?TARGET_IP not set}"
: "${TARGET_PORT:=32400}"
: "${PUBLIC_PORT:=$TARGET_PORT}"

PUB_IF="$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')"

# Forwarding must be on for DNAT to route packets out over the tailnet.
# IPv6 too, so the Tailscale health check stays happy if any v6 route is advertised.
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null

add_nat_rule_if_missing() {
    local chain="$1"; shift
    iptables -t nat -C "$chain" "$@" 2>/dev/null || iptables -t nat -A "$chain" "$@"
}

add_nat_rule_if_missing PREROUTING -i "$PUB_IF" -p tcp --dport "$PUBLIC_PORT" \
    -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"

add_nat_rule_if_missing POSTROUTING -d "$TARGET_IP" -p tcp --dport "$TARGET_PORT" \
    -j MASQUERADE

# Insert at position 1 so it beats any default REJECT further down FORWARD.
iptables -C FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I FORWARD 1 -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
APPLY_EOF
sudo chmod +x /usr/local/sbin/vps-relay-apply.sh

# Apply the rules right now.
sudo TARGET_IP="$TARGET_IP" TARGET_PORT="$TARGET_PORT" PUBLIC_PORT="$PUBLIC_PORT" \
    /usr/local/sbin/vps-relay-apply.sh

printf '\n3.a) Persisting across reboots (two independent mechanisms)...\n\n'

# Mechanism 1 — iptables-persistent: saves the current ruleset and restores it
# early at boot. Fast, but a snapshot can end up empty or get clobbered when
# Docker/Tailscale rebuild the tables, so it's a fast path, not the guarantee.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Mechanism 2 — vps-relay.service: the actual guarantee. A oneshot systemd unit
# that RE-APPLIES the rules on every boot, ordered after the tailnet is up.
# Idempotent (-C checks), so it never stacks duplicates.
sudo tee /etc/systemd/system/vps-relay.service > /dev/null << EOF
[Unit]
Description=VPS tailnet relay (public :$PUBLIC_PORT -> $TARGET_IP:$TARGET_PORT)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=TARGET_IP=$TARGET_IP
Environment=TARGET_PORT=$TARGET_PORT
Environment=PUBLIC_PORT=$PUBLIC_PORT
ExecStart=/usr/local/sbin/vps-relay-apply.sh

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable vps-relay.service

#----------------------------------------------------------------------
# 4) ufw check
#----------------------------------------------------------------------

if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
    printf '\nWARNING: ufw is active. Raw iptables FORWARD/NAT rules can be\n'
    echo "         overridden or ignored by ufw. You likely also need:"
    echo "           sudo ufw allow ${PUBLIC_PORT}/tcp"
    echo "           sudo ufw route allow proto tcp to ${TARGET_IP} port ${TARGET_PORT}"
    echo "         and DEFAULT_FORWARD_POLICY=\"ACCEPT\" in /etc/default/ufw"
    echo "         (then: sudo ufw reload)."
fi

#----------------------------------------------------------------------
# 5) Manual step reminder — cannot be scripted without OCI credentials
#----------------------------------------------------------------------

printf '\n<<< VPS Relay Setup Complete >>>\n\n'
echo "ACTION REQUIRED: open TCP $PUBLIC_PORT from 0.0.0.0/0 in the Oracle Cloud"
echo "console (instance's Security List / NSG ingress rules). This is a"
echo "second, separate firewall from the iptables rules above — both must"
echo "allow the port or the relay won't work."
