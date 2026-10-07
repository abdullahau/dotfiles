#!/usr/bin/env bash
# Personal setup (no sudo). Run after ./system.sh:
#   ./setup.sh    symlink home/ into ~ with GNU Stow + apply desktop settings
set -euo pipefail
cd "$(dirname "$0")"

echo ":: Linking configs into $HOME with GNU Stow"
# Back up any real (non-link) files Stow would otherwise refuse to replace
backup="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
( cd home && find . -mindepth 1 -type f -print0 ) |
while IFS= read -r -d '' f; do
    f="${f#./}"
    # Skip anything that already resolves into this repo (incl. via a linked folder)
    [ "$(readlink -f "$HOME/$f")" = "$PWD/home/$f" ] && continue
    if [ -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        mkdir -p "$backup/$(dirname "$f")"; mv "$HOME/$f" "$backup/$f"
    fi
done
[ -d "$backup" ] && echo "   previous files moved to $backup"
stow -d "$PWD" -t "$HOME" --restow home

# GTK 4 apps read the theme from ~/.config/gtk-4.0 (links into the installed theme)
theme=/usr/share/themes/catppuccin-latte-maroon-standard+default/gtk-4.0
for f in assets gtk.css gtk-dark.css; do ln -sfn "$theme/$f" "$HOME/.config/gtk-4.0/$f"; done

echo ":: Desktop settings that live outside files"
gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-latte-maroon-standard+default'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Light'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.blueman.general plugin-list "['!StatusIcon', '!ShowConnected']"
# clipmenud is started by i3 once the display exists, not at systemd login
systemctl --user disable clipmenud 2>/dev/null || true


if command -v code >/dev/null; then
    echo ":: VS Code extensions (Catppuccin theme + icons)"
    code --install-extension Catppuccin.catppuccin-vsc
    code --install-extension Catppuccin.catppuccin-vsc-icons
fi

echo ":: Done. Reboot to start in i3."
