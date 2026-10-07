# Auto-start the desktop after the silent tty1 auto-login.
# Other ttys (Ctrl+Alt+F2...) still give a normal login prompt.
if status is-login; and test -z "$DISPLAY"; and test "$XDG_VTNR" = 1
    exec startx -- -keeptty >~/.local/share/xorg/startx.log 2>&1
end
