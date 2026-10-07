#!/usr/bin/env bash
# Power menu in the sunset rofi theme. Logout/reboot/shutdown ask to confirm.
suspend="󰤄  Suspend"; logout="󰍃  Log out"; reboot="󰜉  Reboot"; shutdown="󰐥  Shut down"

choice=$(printf '%s\n' "$suspend" "$logout" "$reboot" "$shutdown" |
    rofi -dmenu -i -p power -no-custom -theme-str 'window {width: 300px;} listview {lines: 4;} mode-switcher {enabled: false;}')

confirm() {
    [ "$(printf 'No\nYes\n' | rofi -dmenu -i -p "$1?" -no-custom \
        -theme-str 'window {width: 300px;} listview {lines: 2;} mode-switcher {enabled: false;}')" = Yes ]
}

case "$choice" in
    "$suspend")  systemctl suspend ;;
    "$logout")   confirm "Log out"   && i3-msg exit ;;
    "$reboot")   confirm "Reboot"    && systemctl reboot ;;
    "$shutdown") confirm "Shut down" && systemctl poweroff ;;
esac
