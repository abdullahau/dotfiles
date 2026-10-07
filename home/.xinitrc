#!/bin/sh
# Started by startx from tty1 auto-login (see ~/.config/fish/conf.d/startx.fish)

# System hooks: D-Bus/systemd environment, GTK modules
if [ -d /etc/X11/xinit/xinitrc.d ]; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

# Session environment (EDITOR, BROWSER, Qt theme)
[ -f "$HOME/.profile" ] && . "$HOME/.profile"

exec i3
