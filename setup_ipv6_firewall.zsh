#!/usr/bin/env zsh
#
# setup_ipv6_firewall.zsh — default-deny inbound IPv6 for this host.
#
# Why: e& hands this host a real, routable /64. IPv4 CGNAT had been acting as
# an accidental firewall; IPv6 bypasses it. Scanned from an off-site VPS on
# 2026-09-30, 19 of 26 listening ports answered from the public internet —
# Samba 445/139, sshd, Jellyfin, Navidrome, Tautulli, Stremio, Beszel and the
# Transmission RPC among them. ufw is disabled and e& blocks only 53, 80, 443,
# 8080, 8443 and 8444.
#
# Scope: IPv6 only. Inbound IPv4 cannot reach this host (public 5.107.107.190
# vs local 192.168.0.100 — carrier NAT), so filtering v4 adds risk and no
# protection.
#
# One INPUT chain is enough. The compose networks are IPv4-only, so every IPv6
# connection to a published container port is handled by docker-proxy, which
# binds `-host-ip ::` on the host — host sockets, not forwarded traffic. A
# forward chain is included only to guard against a future `enable_ipv6: true`
# on a compose network.
#
# This uses its own nftables table so it never touches Docker's chains, and it
# never issues `flush ruleset` (that would wipe Docker's rules).
#
# You cannot lock yourself out: tailscale0 and all IPv4 are accepted.
#
# Self-contained. Idempotent and safe to re-run.
#
# Usage:
#   sudo ./setup_ipv6_firewall.zsh              # apply and enable at boot
#   ./setup_ipv6_firewall.zsh dry-run           # print the ruleset, change nothing
#   ./setup_ipv6_firewall.zsh status            # rules, drop counters, v6 listeners
#   sudo ./setup_ipv6_firewall.zsh revert       # remove the table and the unit

set -euo pipefail

# EDIT HERE: allow LAN neighbours to reach this host over IPv6.
# Off by default. LAN clients use 192.168.0.100 (IPv4), which is never
# filtered, so nothing needs this today. Turning it on means the script pins
# the current global /64 — and e& rotates that prefix, so the rule goes stale.
# If you turn it on, re-run the script after a prefix change.
ALLOW_LAN_V6=no

NFT_FILE=/etc/nftables.d/homelab-ipv6.nft
UNIT=/etc/systemd/system/homelab-ipv6-firewall.service
TABLE="inet homelab_fw"
TAILNET6="fd7a:115c:a1e0::/48"   # Tailscale's fixed ULA range

ACTION="${1:-apply}"

WAN_IF="$(ip -6 route show default 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
[[ -n "$WAN_IF" ]] || { print -u2 "no IPv6 default route — nothing to protect, refusing"; exit 1; }

LAN6_RULE="        # LAN neighbours over IPv6: disabled (ALLOW_LAN_V6=no)"
if [[ "$ALLOW_LAN_V6" == yes ]]; then
    PREFIX="$(ip -6 route show dev "$WAN_IF" proto ra 2>/dev/null | awk '/\/64/{print $1; exit}')"
    [[ -n "$PREFIX" ]] || { print -u2 "ALLOW_LAN_V6=yes but no /64 found on $WAN_IF"; exit 1; }
    LAN6_RULE="        ip6 saddr $PREFIX accept"
fi

render_ruleset() {
cat <<NFT
#!/usr/sbin/nft -f
# Managed by setup_ipv6_firewall.zsh — do not edit by hand.
# WAN interface: $WAN_IF

table $TABLE
delete table $TABLE

table $TABLE {
    chain input {
        type filter hook input priority filter - 10; policy accept;

        meta nfproto != ipv6 accept
        iifname "lo" accept
        iifname "tailscale0" accept
        ct state established,related accept

        # ICMPv6 must pass or SLAAC, neighbour discovery and PMTUD all break.
        meta l4proto ipv6-icmp accept

        udp dport 546 accept              # DHCPv6 client
        ip6 saddr fe80::/10 accept        # link-local: RA, ND, on-link peers
        ip6 saddr $TAILNET6 accept        # tailnet
        udp dport 41641 accept            # tailscaled direct connections
$LAN6_RULE

        counter drop comment "inbound IPv6 dropped"
    }

    # Guard only. Nothing is forwarded today: the compose networks are
    # IPv4-only and docker-proxy terminates IPv6 on the host.
    chain forward {
        type filter hook forward priority filter - 10; policy accept;

        meta nfproto != ipv6 accept
        iifname "tailscale0" accept
        oifname "tailscale0" accept
        ct state established,related accept
        meta l4proto ipv6-icmp accept
        ip6 saddr fe80::/10 accept
        ip6 saddr $TAILNET6 accept

        iifname "$WAN_IF" counter drop comment "forwarded IPv6 dropped"
    }
}
NFT
}

case "$ACTION" in
dry-run)
    render_ruleset
    ;;

status)
    print "\n<<< nftables table $TABLE >>>\n"
    sudo nft list table $TABLE 2>/dev/null || print "not loaded"
    print "\n<<< unit >>>"
    systemctl is-enabled homelab-ipv6-firewall.service 2>/dev/null || true
    systemctl is-active homelab-ipv6-firewall.service 2>/dev/null || true
    print "\n<<< IPv6 listeners now protected from the public internet >>>"
    ss -6 -lntu 2>/dev/null | awk 'NR>1{print "  "$1" "$5}' | sort -u
    ;;

revert)
    [[ $EUID -eq 0 ]] || { print -u2 "run with sudo"; exit 1; }
    systemctl disable --now homelab-ipv6-firewall.service 2>/dev/null || true
    nft delete table $TABLE 2>/dev/null || true
    rm -f "$NFT_FILE" "$UNIT"
    systemctl daemon-reload
    print "reverted — inbound IPv6 is unfiltered again"
    ;;

apply)
    [[ $EUID -eq 0 ]] || { print -u2 "run with sudo"; exit 1; }
    print "\n<<< default-deny inbound IPv6 on $WAN_IF >>>\n"

    print "1) Writing $NFT_FILE..."
    install -d -m 755 "${NFT_FILE:h}"
    render_ruleset > "$NFT_FILE"
    chmod 644 "$NFT_FILE"

    print "2) Validating..."
    nft -c -f "$NFT_FILE"

    print "3) Installing $UNIT..."
    cat > "$UNIT" <<UNITEOF
[Unit]
Description=homelab default-deny inbound IPv6
Documentation=file://$NFT_FILE
After=network-online.target docker.service tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $NFT_FILE
ExecStop=/usr/sbin/nft delete table $TABLE
ExecReload=/usr/sbin/nft -f $NFT_FILE

[Install]
WantedBy=multi-user.target
UNITEOF
    chmod 644 "$UNIT"

    print "4) Enabling and loading..."
    systemctl daemon-reload
    systemctl enable --now homelab-ipv6-firewall.service

    print "\nLoaded. Verify from off-net, then watch for these:"
    print "  - any device using this host's IPv6 for DNS (AdGuard on :53)"
    print "  - Tailscale falling back to DERP (check: tailscale status)"
    print "Roll back with: sudo $0 revert\n"
    ;;

*)
    print -u2 "unknown action: $ACTION (apply | dry-run | status | revert)"
    exit 1
    ;;
esac
