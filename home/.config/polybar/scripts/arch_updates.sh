#!/usr/bin/env bash
# Pending package updates for polybar (runs continuously, tail = true).
# Prints the last saved count instantly so the bar never shows a gap, then
# re-checks every 30 min, or within a minute of any pacman run.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/polybar-updates"
log=/var/log/pacman.log

show() {
    if [ "${2:-0}" -gt 0 ]; then echo "%{T6}󰏔%{T-} $1+$2"; else echo "%{T6}󰏔%{T-} $1"; fi
}

[ -r "$cache" ] && show $(cat "$cache") || echo "%{T6}󰏔%{T-} …"

while true; do
    arch=$(checkupdates 2>/dev/null | wc -l)
    if command -v paru >/dev/null; then aur=$(paru -Qum 2>/dev/null | wc -l)
    elif command -v yay >/dev/null; then aur=$(yay -Qum 2>/dev/null | wc -l)
    else aur=0; fi
    echo "$arch $aur" > "$cache"
    show "$arch" "$aur"

    stamp=$(stat -c %Y "$log" 2>/dev/null)
    for _ in $(seq 60); do            # 60 x 30s = 30 min
        sleep 30
        [ "$(stat -c %Y "$log" 2>/dev/null)" != "$stamp" ] && { sleep 5; break; }
    done
done
