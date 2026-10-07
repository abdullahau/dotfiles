#!/usr/bin/env bash
# Restore this i3 setup on a fresh CachyOS/Arch install.
#   ./setup.sh            install packages + symlink home/ with stow + apply settings
#   ./setup.sh --system   also install the files under system/ (needs sudo)
set -euo pipefail
cd "$(dirname "$0")"

pkgs() { sed -n "/^# $1/,/^$/p" packages.txt | grep -v '^#' | tr -s ' \n' ' '; }

echo ":: Installing packages"
sudo pacman -S --needed $(pkgs 'Official')
paru -S --needed $(pkgs 'AUR')

echo ":: Linking configs into $HOME with GNU Stow"
# Back up any real (non-link) files Stow would otherwise refuse to replace
backup="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
( cd home && find . -mindepth 1 -type f -print0 ) |
while IFS= read -r -d '' f; do
    f="${f#./}"
    if [ -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        mkdir -p "$backup/$(dirname "$f")"; mv "$HOME/$f" "$backup/$f"
    fi
done
[ -d "$backup" ] && echo "   previous files moved to $backup"
stow -d "$PWD" -t "$HOME" --restow home

# GTK 4 apps read the theme from ~/.config/gtk-4.0 (links into the installed theme)
theme=/usr/share/themes/catppuccin-mocha-peach-standard+default/gtk-4.0
for f in assets gtk.css gtk-dark.css; do ln -sfn "$theme/$f" "$HOME/.config/gtk-4.0/$f"; done

echo ":: Desktop settings that live outside files"
gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-peach-standard+default'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.blueman.general plugin-list "['!StatusIcon', '!ShowConnected']"
# clipmenud is started by i3 once the display exists, not at systemd login
systemctl --user disable clipmenud 2>/dev/null || true

if [ "${1:-}" = "--system" ]; then
    echo ":: System files (sudo)"
    sudo install -Dm644 system/etc/systemd/system/getty@tty1.service.d/autologin.conf \
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
    sudo install -Dm644 system/etc/locale.conf /etc/locale.conf
    sudo install -Dm644 system/etc/default/grub /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    sudo systemctl disable ly@tty2.service 2>/dev/null || true
    sudo systemctl enable --now paccache.timer
fi

echo ":: Done. Reboot to start in i3."
