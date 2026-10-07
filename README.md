# dotfiles: i3 "sunset" setup (CachyOS, Dell Latitude)

i3 + polybar + rofi + picom, themed from the Axyl OS sunset wallpaper.
Palette: navy `#17232C`, slate `#2F3849`, text `#E8DCE0`, muted `#7D8799`,
peach `#E6B18B`, coral `#C26967`.

## Layout
| Path | Goes to |
|---|---|
| `home/` | `~`, as symlinks made by GNU Stow (edit files here or via `~/.config/…`, same file) |
| `system/` | `/` (needs sudo) |
| `packages.txt` | packages the setup relies on |
| `setup.sh` | installs packages, stows `home/`, applies settings; `--system` also installs `system/` |

## What's in it
- **i3**: `~/.config/i3/config` (sections: basics, apps, windows, workspaces, Fn keys, rules, startup), `xob.sh` (volume/brightness OSD)
- **polybar**: config, `launch.sh` (single start at login, logs to `$XDG_RUNTIME_DIR/polybar-*.log`), `scripts/arch_updates.sh` (cached update count), `scripts/bluetooth.sh`
- **rofi**: `sunset.rasi` theme, `keyhelp.py` (Super+/ shortcut list built from the i3 config), `powermenu.sh` (Super+Esc / Super+Shift+E)
- **picom, dunst, alacritty, xob, flameshot**: sunset colours, no animations
- **GTK 2/3/4, Kvantum, Papirus**: Catppuccin Mocha (peach), no animations
- **Login**: tty1 auto-login (`system/.../getty@tty1.service.d/autologin.conf`) → fish `conf.d/startx.fish` → `~/.xinitrc` (loads `~/.profile`) → i3. No display manager.
- **System**: `/etc/default/grub` (hidden menu, 0s), `/etc/locale.conf` (English time format, UAE regional formats)

## Settings not stored in files (applied by setup.sh)
- gsettings: GTK theme, Papirus-Dark icons, dark colour scheme, animations off
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
