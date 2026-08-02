#!/usr/bin/env zsh
#
# Enable TCP BBR congestion control + fq pacing + high bandwidth-delay-product
# socket buffers on the ORACLE VPS RELAY.
#
# Why: the VPS is the *sender* on the last leg to your viewers (VPS -> UAE /
# Thailand). BBR here is what improves the throughput and start/seek times the
# viewers actually feel. Pairs with setup_bbr_server.zsh (which tunes the home
# server end of the same relay). See setup_vps_relay.zsh for the relay itself.
#
# Safe to re-run: the sysctl drop-in and modules-load file are rewritten fresh
# and the module load is idempotent.
#
# Usage:  ./setup_bbr_vps.zsh          (run ON the Oracle VPS; will sudo)

setopt nounset

echo "\n<<< Enabling BBR + fq + high-BDP TCP buffers (Oracle VPS) >>>\n"

#----------------------------------------------------------------------
# 1) Confirm the kernel actually ships the BBR module
#----------------------------------------------------------------------

echo "1) Checking BBR availability for kernel $(uname -r)...\n"

if ! modinfo tcp_bbr > /dev/null 2>&1; then
    echo "ERROR: tcp_bbr module not found for this kernel."
    echo "       Install a kernel that ships it (any modern Ubuntu/Oracle kernel does), then re-run."
    exit 1
fi

#----------------------------------------------------------------------
# 2) Persist the sysctl settings
#----------------------------------------------------------------------

echo "2) Writing /etc/sysctl.d/99-bbr.conf...\n"

sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null << 'EOF'
# BBR congestion control + fair-queue pacing + high bandwidth-delay-product
# buffers. Big win for single TCP streams over long-RTT paths (VPS -> viewer).
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

echo "3) Loading tcp_bbr now and on every boot...\n"

echo tcp_bbr | sudo tee /etc/modules-load.d/bbr.conf > /dev/null
sudo modprobe tcp_bbr

#----------------------------------------------------------------------
# 4) Apply
#----------------------------------------------------------------------

echo "4) Applying sysctl settings...\n"

sudo sysctl --system > /dev/null

#----------------------------------------------------------------------
# 5) Verify
#----------------------------------------------------------------------

cc=$(sysctl -n net.ipv4.tcp_congestion_control)
qd=$(sysctl -n net.core.default_qdisc)

echo "\n<<< Result >>>"
echo "  congestion control : $cc"
echo "  default qdisc      : $qd"
echo "  wmem_max           : $(sysctl -n net.core.wmem_max)"

if [[ "$cc" == "bbr" && "$qd" == "fq" ]]; then
    echo "\nBBR is active. Persists across reboots via /etc/sysctl.d/99-bbr.conf"
    echo "and /etc/modules-load.d/bbr.conf."
    echo "To revert: sudo rm /etc/sysctl.d/99-bbr.conf /etc/modules-load.d/bbr.conf && sudo sysctl --system"
else
    echo "\nWARNING: expected bbr/fq but got $cc/$qd — check the output above."
    exit 1
fi
