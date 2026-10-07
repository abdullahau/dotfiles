# dotfiles: i3 + Catppuccin Latte (CachyOS, Dell Latitude)

i3 + polybar + rofi + picom, all on Catppuccin Latte (light) with the maroon accent.
Main colours: base `#eff1f5`, text `#4c4f69`, muted `#8c8fa1`, surface `#ccd0da`,
maroon `#e64553` (the one accent: borders, current workspace, selections), red `#d20f39` (alerts).

## Layout
| Path | Goes to |
|---|---|
| `home/` | `~`, as symlinks made by GNU Stow (edit files here or via `~/.config/…`, same file) |
| `packages.txt` | packages the setup relies on |
| `system.sh` | **sudo part**: packages (pacman + AUR), GRUB, locale, tty1 auto-login, SSH + firewall, cache cleanup |
| `setup.sh` | **personal part**: stows `home/` into `~`, applies desktop settings |

Fresh install: `./system.sh`, then `./setup.sh`, then reboot.

## What's in it
- **i3**: `~/.config/i3/config` (sections: basics, apps, windows, workspaces, Fn keys, rules, startup), `xob.sh` (volume/brightness OSD)
- **polybar**: config, `launch.sh` (single start at login, logs to `$XDG_RUNTIME_DIR/polybar-*.log`), `scripts/arch_updates.sh` (cached update count), `scripts/bluetooth.sh`
- **rofi**: `latte.rasi` theme, `keyhelp.py` (Super+/ shortcut list built from the i3 config), `powermenu.sh` (Super+Esc / Super+Shift+E)
- **alacritty, dunst, btop, micro, VS Code**: official Catppuccin Latte colours; btop and micro have no background so the terminal's 90% opacity shows through
- **picom, xob, flameshot**: Latte colours, no animations
- **GTK 3/4, Kvantum, Papirus**: Catppuccin Latte (maroon), no animations. The GTK theme is the official release zip in `~/.local/share/themes` (setup.sh downloads it), not an AUR package
- **Login**: tty1 auto-login (getty override written by `system.sh`) → fish `conf.d/startx.fish` → `~/.xinitrc` (loads `~/.profile`) → i3. No display manager.
- **yazi**: hidden files shown, micro as editor
- **System** (`system.sh`): GRUB hidden menu with 0s timeout, `LC_TIME=en_GB.UTF-8`, sshd + ufw (port 22), paccache.timer

## Settings not stored in files (applied by setup.sh)
- gsettings: GTK theme, Papirus-Light icons, light colour scheme, animations off
- blueman: tray icon plugins off (`!StatusIcon`, `!ShowConnected`)
- `clipmenud` user service disabled at login (i3 starts it once X is up)

## Manual extras
- Fn lock: `Fn+Esc`
- Boot menu: hold Shift / tap Esc after the Dell logo
- Undo auto-login: delete the getty override and `sudo systemctl enable ly@tty2.service`

## Day to day
- Edit configs where they normally live; they are symlinks into this repo. Then `git -C ~/.dotfiles commit -am "…"`.
- New config file: move it into `home/` at the same path, then `stow -d ~/.dotfiles -t ~ --restow home`.
- If an app replaced a symlink with a real file (flameshot or Kvantum Manager saving settings can do this),
  copy it back into `home/` and `--restow`; `git status` shows the change.
- `sed -i` replaces a symlink with a plain file; use `sed -i --follow-symlinks`, or edit the copy in `home/`.
