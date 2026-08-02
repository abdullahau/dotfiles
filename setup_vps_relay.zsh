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

# Add an iptables rule only if an equivalent one isn't already present, so
# re-running this script doesn't pile up duplicate DNAT/MASQUERADE/FORWARD
# rules.
add_nat_rule_if_missing() {
    local chain=$1; shift
    if sudo iptables -t nat -C "$chain" "$@" 2>/dev/null; then
        echo "  (nat/$chain rule already present, skipping)"
    else
        sudo iptables -t nat -A "$chain" "$@"
    fi
}

insert_forward_rule_if_missing() {
    if sudo iptables -C FORWARD "$@" 2>/dev/null; then
        echo "  (FORWARD rule already present, skipping)"
    else
        # Insert at position 1 so it's evaluated before any default REJECT.
        sudo iptables -I FORWARD 1 "$@"
    fi
}

add_nat_rule_if_missing PREROUTING -i "$PUB_IF" -p tcp --dport "$PUBLIC_PORT" \
    -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"

add_nat_rule_if_missing POSTROUTING -d "$TARGET_IP" -p tcp --dport "$TARGET_PORT" \
    -j MASQUERADE

insert_forward_rule_if_missing -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT

echo "\n3.a) Persisting iptables rules across reboots...\n"

# iptables-persistent's postinst asks an interactive "save current rules?"
# debconf question; preseed it so apt install doesn't hang non-interactively.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

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
