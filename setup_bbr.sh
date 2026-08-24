#!/usr/bin/env bash
#
# setup_bbr.sh — enable TCP BBR congestion control, fq pacing, and large socket
# buffers. Speeds up single TCP streams over long-RTT paths. Takes no inputs.
# Run it on both the VPS and the home server.
#
# Usage: ./setup_bbr.sh   (calls sudo itself). Idempotent and safe to re-run.

set -euo pipefail

printf '\n<<< Enabling BBR + fq + high-BDP TCP buffers >>>\n\n'

#----------------------------------------------------------------------
# 1) Confirm the kernel actually ships the BBR module
#----------------------------------------------------------------------

printf '1) Checking BBR availability for kernel %s...\n\n' "$(uname -r)"

if ! modinfo tcp_bbr > /dev/null 2>&1; then
    echo "ERROR: tcp_bbr module not found for this kernel."
    echo "       Install a kernel that ships it (any modern Ubuntu/Oracle kernel does), then re-run."
    exit 1
fi

#----------------------------------------------------------------------
# 2) Persist the sysctl settings
#----------------------------------------------------------------------

printf '2) Writing /etc/sysctl.d/99-bbr.conf...\n\n'

sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null << 'EOF'
# BBR congestion control + fair-queue pacing + high bandwidth-delay-product
# buffers. Big win for single TCP streams over long-RTT paths.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
EOF

#----------------------------------------------------------------------
# 3) Load the module now and on every boot
#
#    Order matters: load the module before `sysctl --system` runs, or setting
#    tcp_congestion_control=bbr fails with "invalid argument".
#----------------------------------------------------------------------

printf '3) Loading tcp_bbr now and on every boot...\n\n'

echo tcp_bbr | sudo tee /etc/modules-load.d/bbr.conf > /dev/null
sudo modprobe tcp_bbr

#----------------------------------------------------------------------
# 4) Apply
#----------------------------------------------------------------------

printf '4) Applying sysctl settings...\n\n'

sudo sysctl --system > /dev/null

# fq only applies to interfaces brought up after the sysctl is set. Attach it to
# the live interface now, so no reboot is needed.
IFACE="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)"
if [[ -n "${IFACE:-}" ]] && command -v tc >/dev/null 2>&1; then
    sudo tc qdisc replace dev "$IFACE" root fq && echo "  attached fq to $IFACE (live, no reboot needed)"
fi

#----------------------------------------------------------------------
# 5) Verify
#----------------------------------------------------------------------

cc="$(sysctl -n net.ipv4.tcp_congestion_control)"
qd="$(sysctl -n net.core.default_qdisc)"

printf '\n<<< Result >>>\n'
echo "  congestion control : $cc"
echo "  default qdisc      : $qd"
echo "  wmem_max           : $(sysctl -n net.core.wmem_max)"
if [[ -n "${IFACE:-}" ]] && command -v tc >/dev/null 2>&1; then
    echo "  live NIC qdisc     : $(tc qdisc show dev "$IFACE" 2>/dev/null | grep -oE 'qdisc [a-z_]+' | head -1 | awk '{print $2}') (on $IFACE)"
fi

if [[ "$cc" == "bbr" && "$qd" == "fq" ]]; then
    printf '\nBBR is active. Persists across reboots via /etc/sysctl.d/99-bbr.conf and /etc/modules-load.d/bbr.conf.\n'
    echo "To revert: sudo rm /etc/sysctl.d/99-bbr.conf /etc/modules-load.d/bbr.conf && sudo sysctl --system"
else
    printf '\nWARNING: expected bbr/fq but got %s/%s — check the output above.\n' "$cc" "$qd"
    exit 1
fi
