#!/usr/bin/env bash
#
# Self-contained port of setup_bbr_server.zsh / setup_bbr_vps.zsh — pure bash,
# no zsh, no .env, no brew, no dotfiles bootstrap. Copy this ONE file anywhere
# and run it. The tuning is identical on the home server and the VPS, so this
# single script serves both ends of the relay.
#
# Enables TCP BBR congestion control + fq pacing + high bandwidth-delay-product
# socket buffers. Big win for single TCP streams over long-RTT paths, where the
# stock `cubic` + small buffers cap a flow well below the link's real capacity.
#
# Safe to re-run: the sysctl drop-in and modules-load file are rewritten fresh
# and the module load is idempotent.
#
# Usage:  ./setup_bbr.sh          (run on the target machine; will sudo)

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
# 3) Load the module now AND on every boot
#
#    ORDER MATTERS: the module must be loaded BEFORE `sysctl --system`
#    runs, otherwise setting tcp_congestion_control=bbr is rejected as
#    "invalid argument" (bbr isn't in tcp_available_congestion_control yet).
#----------------------------------------------------------------------

printf '3) Loading tcp_bbr now and on every boot...\n\n'

echo tcp_bbr | sudo tee /etc/modules-load.d/bbr.conf > /dev/null
sudo modprobe tcp_bbr

#----------------------------------------------------------------------
# 4) Apply
#----------------------------------------------------------------------

printf '4) Applying sysctl settings...\n\n'

sudo sysctl --system > /dev/null

#----------------------------------------------------------------------
# 5) Verify
#----------------------------------------------------------------------

cc="$(sysctl -n net.ipv4.tcp_congestion_control)"
qd="$(sysctl -n net.core.default_qdisc)"

printf '\n<<< Result >>>\n'
echo "  congestion control : $cc"
echo "  default qdisc      : $qd"
echo "  wmem_max           : $(sysctl -n net.core.wmem_max)"

if [[ "$cc" == "bbr" && "$qd" == "fq" ]]; then
    printf '\nBBR is active. Persists across reboots via /etc/sysctl.d/99-bbr.conf and /etc/modules-load.d/bbr.conf.\n'
    echo "To revert: sudo rm /etc/sysctl.d/99-bbr.conf /etc/modules-load.d/bbr.conf && sudo sysctl --system"
else
    printf '\nWARNING: expected bbr/fq but got %s/%s — check the output above.\n' "$cc" "$qd"
    exit 1
fi
