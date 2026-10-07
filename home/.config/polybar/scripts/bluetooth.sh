#!/usr/bin/env bash
# Bluetooth status for polybar.
#   off            -> radio blocked / no controller
#   on             -> powered, nothing connected
#   <device name>  -> connected device(s)
# Usage: bluetooth.sh [toggle]

if [ "$1" = toggle ]; then
    # On: unblock the radio and power the adapter up.
    # Off: block the radio entirely (same as the laptop's airplane key).
    if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
        bluetoothctl power off >/dev/null 2>&1
        rfkill block bluetooth
    else
        rfkill unblock bluetooth
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            bluetoothctl power on >/dev/null 2>&1 && break
            sleep 0.3
        done
    fi
    exit
fi

if ! bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
    echo "%{F#7D8799}%{T6}󰂲%{T-} off%{F-}"
    exit
fi

devices=$(bluetoothctl devices Connected 2>/dev/null | cut -d' ' -f3- | paste -sd ',' | sed 's/,/, /g')
if [ -n "$devices" ]; then
    echo "%{T6}󰂱%{T-} $devices"
else
    echo "%{T6}󰂯%{T-} on"
fi
