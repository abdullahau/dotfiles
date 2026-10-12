#!/usr/bin/env bash
# Privacy + security hardening (uses sudo). Run as your normal user; system.sh runs it at the end:
#   ./harden.sh
# Safe to re-run: every step overwrites its own files with the same result.
# Keeps Tailscale working and AdGuard (on homelab, via the tailnet) as the DNS resolver.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user (sudo is used where needed)."; exit 1; }

ADGUARD=100.125.140.11   # homelab's tailnet IP, the resolver set in the Tailscale admin console

step() { printf '\n:: %s\n' "$*"; }
# put FILE: write stdin to a root-owned file
put() { sudo install -d "$(dirname "$1")"; sudo tee "$1" >/dev/null; }

step "Packages this script relies on (also in packages.txt, installed by system.sh)"
sudo pacman -S --needed --noconfirm tailscale bind jq ufw openssh opensnitch qt5-svg resvg

step "DNS: AdGuard over Tailscale, Wi-Fi router's DNS only as fallback, nothing else"
# Tailscale routes every query (~.) to AdGuard. With Tailscale down, its DNS goes away and the
# network's own DNS answers. No hidden Google/Cloudflare/Quad9 fallback, no LLMNR/mDNS
# broadcasting the hostname on every network.
put /etc/systemd/resolved.conf.d/90-privacy.conf <<'EOF'
[Resolve]
FallbackDNS=
LLMNR=no
MulticastDNS=no
EOF
sudo systemctl restart systemd-resolved

# Tailscale up but AdGuard unreachable: stop using Tailscale DNS until it answers again
put /usr/local/bin/dns-failover <<EOF
#!/bin/sh
# AdGuard answers -> Tailscale DNS on; no answer -> off (the network's DNS takes over)
tailscale status >/dev/null 2>&1 || exit 0
if dig +time=2 +tries=2 @$ADGUARD . NS >/dev/null 2>&1; then want=true; else want=false; fi
have=\$(tailscale debug prefs | jq -r .CorpDNS)
[ "\$have" = "\$want" ] || { tailscale set --accept-dns=\$want; logger -t dns-failover "accept-dns=\$want"; }
EOF
sudo chmod 755 /usr/local/bin/dns-failover
put /etc/systemd/system/dns-failover.service <<'EOF'
[Unit]
Description=Switch Tailscale DNS off while AdGuard is unreachable
After=tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dns-failover
EOF
put /etc/systemd/system/dns-failover.timer <<'EOF'
[Unit]
Description=Check AdGuard reachability every 30s

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now dns-failover.timer

step "NetworkManager: no connectivity pings, random MAC per network, no hostname in DHCP"
# Connectivity check = HTTP request to ping.archlinux.org on every connect (captive-portal
# detection only). MAC is random but stable per network, so the home router sees one new device.
put /etc/NetworkManager/conf.d/90-privacy.conf <<'EOF'
[connectivity]
enabled=false

[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
ipv6.ip6-privacy=2
EOF
sudo systemctl reload NetworkManager

step "Firewall: deny incoming, SSH only from the tailnet"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw delete allow 22 >/dev/null 2>&1 || true
sudo ufw delete allow 22/tcp >/dev/null 2>&1 || true
sudo ufw allow in on tailscale0 to any port 22 proto tcp
sudo ufw --force enable

step "SSH: keys only, no root, only $USER"
# Earlier drop-ins win in sshd, so 10- overrides the distro's 20-/99- files
pw=yes
if [ -s "$HOME/.ssh/authorized_keys" ]; then
    pw=no
else
    echo "   ~/.ssh/authorized_keys is empty: password login stays ON so you are not locked out."
    echo "   Add a key (ssh-copy-id from another device), then re-run ./harden.sh."
fi
put /etc/ssh/sshd_config.d/10-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication $pw
KbdInteractiveAuthentication no
AllowUsers $USER
X11Forwarding no
MaxAuthTries 3
EOF
sudo sshd -t
sudo systemctl reload sshd

step "Kernel: extra hardening sysctls"
# rp_filter loose (2): strict mode breaks Tailscale exit nodes
put /etc/sysctl.d/90-hardening.conf <<'EOF'
fs.suid_dumpable = 0
kernel.kexec_load_disabled = 1
dev.tty.ldisc_autoload = 0
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
sudo sysctl --system >/dev/null

step "Crash dumps: not written to disk (they can hold passwords and keys from memory)"
put /etc/systemd/coredump.conf.d/90-off.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

step "Firefox: telemetry, studies, sponsored content and its own DNS-over-HTTPS off (locked)"
# DoH off keeps Firefox on the system resolver, i.e. AdGuard
put /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisableFeedbackCommands": true,
    "DisablePocket": true,
    "DNSOverHTTPS": { "Enabled": false, "Locked": true },
    "CaptivePortal": false,
    "NetworkPrediction": false,
    "FirefoxHome": { "SponsoredTopSites": false, "SponsoredStories": false, "Stories": false, "Locked": true },
    "FirefoxSuggest": { "SponsoredSuggestions": false, "ImproveSuggest": false, "Locked": true },
    "UserMessaging": { "ExtensionRecommendations": false, "FeatureRecommendations": false, "SkipOnboarding": true, "MoreFromMozilla": false, "Locked": true },
    "Preferences": {
      "browser.crashReports.unsubmittedCheck.autoSubmit2": { "Value": false, "Status": "locked" },
      "browser.newtabpage.activity-stream.feeds.telemetry": { "Value": false, "Status": "locked" },
      "browser.newtabpage.activity-stream.telemetry": { "Value": false, "Status": "locked" },
      "browser.ping-centre.telemetry": { "Value": false, "Status": "locked" }
    }
  }
}
EOF

step "OpenSnitch: asks before any program connects out"
rules=/etc/opensnitchd/rules
# allow NAME OPERAND DATA: a permanent allow rule
allow() {
    put "$rules/$1.json" <<EOF
{
  "created": "2026-10-12T00:00:00Z",
  "updated": "2026-10-12T00:00:00Z",
  "name": "$1",
  "description": "harden.sh",
  "enabled": true,
  "precedence": true,
  "action": "allow",
  "duration": "always",
  "operator": { "type": "$( [[ $2 == *network ]] && echo network || echo simple )", "operand": "$2", "sensitive": false, "data": "$3", "list": [] }
}
EOF
}
# Plumbing that must never wait for a prompt
allow 000-tailscaled      process.path /usr/bin/tailscaled
allow 000-resolved        process.path /usr/lib/systemd/systemd-resolved
allow 000-networkmanager  process.path /usr/bin/NetworkManager
allow 000-timesyncd       process.path /usr/lib/systemd/systemd-timesyncd
allow 000-pacman          process.path /usr/bin/pacman
allow 000-dig             process.path /usr/bin/dig
# Local traffic and your own tailnet devices are not "outside"
allow 001-loopback-v4     dest.network 127.0.0.0/8
allow 001-loopback-v6     dest.network ::1/128
allow 001-tailnet-v4      dest.network 100.64.0.0/10
allow 001-tailnet-v6      dest.network fd7a:115c:a1e0::/48
# UI closed: saved rules still apply, new connections are allowed. Open "OpenSnitch" from rofi for prompts
cfg=/etc/opensnitchd/default-config.json
[ -f "$cfg" ] && sudo sh -c "jq '.DefaultAction=\"allow\"' $cfg > $cfg.new && mv $cfg.new $cfg"
sudo systemctl enable --now opensnitchd
sudo systemctl restart opensnitchd

# Tray icons: Papirus-Light's OpenSnitch set in Latte colours (assets/opensnitch), copied over the
# stock ones after every opensnitch install/upgrade. The app reads them from its own res/ dir.
# "connected" is an SVG, so qt5-svg must be installed or that icon is blank.
icons=/usr/local/share/opensnitch-icons
sudo install -d "$icons"
sudo install -m644 assets/opensnitch/opensnitch-tray.svg "$icons/icon-white.svg"
for s in off red pause alert; do
    resvg -w 64 -h 64 "assets/opensnitch/opensnitch-tray-$s.svg" /dev/stdout | sudo tee "$icons/icon-$s.png" >/dev/null
done
put /usr/local/bin/opensnitch-icons <<EOF
#!/bin/sh
for res in /usr/lib/python3*/site-packages/opensnitch/res; do cp $icons/* "\$res/"; done
EOF
sudo chmod 755 /usr/local/bin/opensnitch-icons
put /etc/pacman.d/hooks/opensnitch-icons.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = opensnitch

[Action]
Description = Catppuccin Latte tray icons for OpenSnitch
When = PostTransaction
Exec = /usr/local/bin/opensnitch-icons
EOF
sudo /usr/local/bin/opensnitch-icons

printf '\n:: Hardening done. Check: resolvectl status; sudo ufw status; then open OpenSnitch from rofi (quit it first if it is running).\n'
