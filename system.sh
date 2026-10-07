#!/usr/bin/env bash
# System-level setup (uses sudo). Run as your normal user, before setup.sh:
#   ./system.sh
# Safe to re-run: every step checks or overwrites to the same result.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user (sudo is used where needed)."; exit 1; }

step() { printf '\n:: %s\n' "$*"; }
pkgs() { sed -n "/^# $1/,/^$/p" packages.txt | grep -v '^#' | tr -s ' \n' ' '; }
# set_conf FILE KEY VALUE: replace KEY=... or append it
set_conf() {
    if sudo grep -qE "^\s*#?\s*$2=" "$1"; then
        sudo sed -i -E "s|^\s*#?\s*$2=.*|$2=$3|" "$1"
    else
        echo "$2=$3" | sudo tee -a "$1" >/dev/null
    fi
}

step "Packages (official repos)"
sudo pacman -S --needed $(pkgs 'Official')

step "Packages (AUR, via paru)"
paru -S --needed $(pkgs 'AUR')

step "GRUB: hidden menu, no wait (hold Shift / tap Esc at boot to see it)"
set_conf /etc/default/grub GRUB_TIMEOUT 0
set_conf /etc/default/grub GRUB_TIMEOUT_STYLE hidden

step "Boot: no splash screen (Plymouth removed, ~3s faster)"
# 1. kernel option, 2. initramfs hook, 3. packages (hook must go before the package)
sudo sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { s/(["'"'"' ])splash( |(["'"'"']))/\1\3/; s/  +/ /g }' /etc/default/grub
sudo sed -i -E '/^HOOKS=/ s/ plymouth//' /etc/mkinitcpio.conf
plymouth_pkgs=$(pacman -Qq plymouth cachyos-plymouth-bootanimation cachyos-plymouth-theme 2>/dev/null || true)
[ -n "$plymouth_pkgs" ] && sudo pacman -Rns --noconfirm $plymouth_pkgs
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg

step "Locale: English (UK) time format, other regional formats unchanged"
if ! locale -a | grep -qi '^en_GB\.utf8$'; then
    sudo sed -i 's/^#\s*en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
fi
set_conf /etc/locale.conf LC_TIME en_GB.UTF-8

step "Login: silent auto-login on tty1 as $USER, no login screen"
sudo install -d /etc/systemd/system/getty@tty1.service.d
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --skip-login --nonewline --noissue --noclear --login-options "-f %s" %%I $TERM\n' "$USER" |
    sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null
sudo systemctl daemon-reload
for dm in ly@tty2.service ly.service sddm.service lightdm.service gdm.service; do
    systemctl is-enabled "$dm" >/dev/null 2>&1 && sudo systemctl disable "$dm"
done

step "Touchpad: natural scrolling in every app (libinput)"
sudo install -d /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf >/dev/null <<'XORG'
Section "InputClass"
    Identifier "touchpad natural scrolling"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "NaturalScrolling" "true"
EndSection
XORG

step "SSH server + firewall (port 22 allowed)"
sudo systemctl enable --now sshd
sudo ufw allow 22
sudo ufw --force enable
sudo systemctl enable ufw

step "Background services: off unless needed"
# Printing starts on demand through the socket; nothing runs until you print
sudo systemctl disable --now cups.service cups.path 2>/dev/null || true
sudo systemctl enable cups.socket 2>/dev/null || true
# Network device discovery (printers/AirPlay) and boot-time wait for network
for u in avahi-daemon.service avahi-daemon.socket NetworkManager-wait-online.service; do
    sudo systemctl disable --now "$u" 2>/dev/null || true
done

step "Weekly package cache cleanup"
sudo systemctl enable --now paccache.timer

printf '\n:: System setup done. Next: ./setup.sh, then reboot.\n'
