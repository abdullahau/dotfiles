#!/usr/bin/env zsh
#
# Turns a public VPS into a tailnet relay: joins Tailscale, enables IP
# forwarding, and DNATs one public TCP port through to a service living on
# another tailnet node (e.g. Plex on the home server, reached over Tailscale
# instead of exposing the home connection directly).
#
# Usage:
#   ./setup_vps_relay.zsh <target-tailnet-ip> [port] [public-port]
#
# Example (Plex, same port in and out):
#   ./setup_vps_relay.zsh 100.125.140.11 32400
#
# Safe to re-run: every iptables rule is checked with `-C` before it's added,
# and the sysctl drop-in is written fresh each time.
#
# Reboot persistence uses TWO independent mechanisms so the relay always
# comes back (see section 3.a):
#   1. iptables-persistent  — restores the saved ruleset snapshot at boot.
#   2. vps-relay.service    — a systemd oneshot that RE-APPLIES the rules on
#                             every boot (after tailscaled/docker), so the
#                             relay survives even if the snapshot is empty,
#                             stale, or flushed by Docker/Tailscale.

setopt nounset

DOTFILES_DIR="${0:A:h}"

if [[ -f "$DOTFILES_DIR/.env" ]]; then
    set -a
    source "$DOTFILES_DIR/.env"
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

echo "\n<<< Starting VPS Relay Setup (public:$PUBLIC_PORT -> $TARGET_IP:$TARGET_PORT) >>>\n"

#----------------------------------------------------------------------
# 1) Join the tailnet
#----------------------------------------------------------------------

echo "\n1) Setting up Tailscale...\n"

curl -fsSL https://tailscale.com/install.sh | sh
if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}"
else
    echo "WARNING: TAILSCALE_AUTH_KEY not set (missing .env?); skipping automatic 'tailscale up'."
    echo "         Run manually: sudo tailscale up"
fi

echo "This VPS's tailnet IP (for reference, not used below):"
tailscale ip -4 2>/dev/null || echo "  (unavailable — tailscale not up yet)"

#----------------------------------------------------------------------
# 2) Enable IP forwarding
#----------------------------------------------------------------------

echo "\n2) Enabling IPv4 forwarding...\n"

sudo tee /etc/sysctl.d/99-vps-relay.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system > /dev/null

#----------------------------------------------------------------------
# 3) Forward public port -> target over the tailnet
#----------------------------------------------------------------------

echo "\n3) Forwarding public :$PUBLIC_PORT -> $TARGET_IP:$TARGET_PORT over the tailnet...\n"

PUB_IF=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')
echo "Detected public interface: $PUB_IF"

# The rule logic lives in a standalone apply script installed to
# /usr/local/sbin. Keeping it in one place means the "set up now" path and
# the "restore on every boot" path (systemd service, 3.a) run the EXACT same
# idempotent logic — no drift. It reads TARGET_IP/TARGET_PORT/PUBLIC_PORT from
# the environment and detects the public interface itself, so it needs no
# arguments at boot.
sudo tee /usr/local/sbin/vps-relay-apply.sh > /dev/null << 'APPLY_EOF'
#!/usr/bin/env bash
# Managed by setup_vps_relay.zsh — do not edit by hand.
# Idempotently (re-)applies the tailnet relay iptables rules. Run once at
# setup and again on every boot via vps-relay.service.
set -euo pipefail

: "${TARGET_IP:?TARGET_IP not set}"
: "${TARGET_PORT:=32400}"
: "${PUBLIC_PORT:=$TARGET_PORT}"

PUB_IF="$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')"

# Forwarding must be on for DNAT to route packets out over the tailnet.
sysctl -w net.ipv4.ip_forward=1 > /dev/null

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

echo "\n3.a) Persisting across reboots (two independent mechanisms)...\n"

# Mechanism 1 — iptables-persistent: saves the current ruleset and restores
# the snapshot early at boot. Fast, but a snapshot can end up empty or get
# clobbered when Docker/Tailscale rebuild the tables, which is how the relay
# silently died once before. So it's a fast path, not the guarantee.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Mechanism 2 — vps-relay.service: the actual guarantee. A oneshot systemd
# unit that RE-APPLIES the rules on every boot, ordered after the tailnet and
# Docker are up. Idempotent (-C checks), so it never stacks duplicates even
# when mechanism 1 already restored the same rules.
sudo tee /etc/systemd/system/vps-relay.service > /dev/null << EOF
[Unit]
Description=VPS tailnet relay (public :$PUBLIC_PORT -> $TARGET_IP:$TARGET_PORT)
After=network-online.target tailscaled.service docker.service
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
    echo "\nWARNING: ufw is active. Raw iptables FORWARD/NAT rules can be"
    echo "         overridden or ignored by ufw. You likely also need:"
    echo "           sudo ufw allow ${PUBLIC_PORT}/tcp"
    echo "           sudo ufw route allow proto tcp to ${TARGET_IP} port ${TARGET_PORT}"
    echo "         and DEFAULT_FORWARD_POLICY=\"ACCEPT\" in /etc/default/ufw"
    echo "         (then: sudo ufw reload)."
fi

#----------------------------------------------------------------------
# 5) Manual step reminder — cannot be scripted without OCI credentials
#----------------------------------------------------------------------

echo "\n<<< VPS Relay Setup Complete >>>\n"
echo "ACTION REQUIRED: open TCP $PUBLIC_PORT from 0.0.0.0/0 in the Oracle Cloud"
echo "console (instance's Security List / NSG ingress rules). This is a"
echo "second, separate firewall from the iptables rules above — both must"
echo "allow the port or the relay won't work."
