#!/usr/bin/env bash
# Power profile (power-profiles-daemon) for polybar.
#   power-saver -> leaf
#   balanced    -> scales
#   performance -> rocket, red
# Usage: power_profile.sh          print now, then again on every change (tail = true)
#        power_profile.sh next|prev  cycle power-saver -> balanced -> performance

profiles=(power-saver balanced performance)

if [ "$1" = next ] || [ "$1" = prev ]; then
    current=$(powerprofilesctl get)
    for i in "${!profiles[@]}"; do [ "${profiles[$i]}" = "$current" ] && break; done
    step=1; [ "$1" = prev ] && step=-1
    powerprofilesctl set "${profiles[$(( (i + step + 3) % 3 ))]}"
    exit
fi

show() {
    case $1 in
        power-saver) echo "%{T2}󰌪%{T-} saver" ;;
        performance) echo "%{F#d20f39}%{T2}󰓅%{T-} perf%{F-}" ;;
        balanced)    echo "%{T2}󰾅%{T-} balanced" ;;
        *)           echo "%{F#8c8fa1}%{T2}󰾅%{T-} n/a%{F-}" ;;
    esac
}

show "$(powerprofilesctl get 2>/dev/null)"
# The daemon announces every change (from here, a settings app, or the CLI)
gdbus monitor --system --dest org.freedesktop.UPower.PowerProfiles \
        --object-path /org/freedesktop/UPower/PowerProfiles 2>/dev/null |
    while read -r line; do
        [[ $line =~ \'ActiveProfile\':\ \<\'([a-z-]+)\'\> ]] && show "${BASH_REMATCH[1]}"
    done
