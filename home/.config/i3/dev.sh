#!/usr/bin/env bash
# Super+F2: build the dev layout (dev.json) on the current workspace:
# VS Code left, Firefox top right, Alacritty bottom right.
# Only runs on an empty workspace, so it never mixes with windows already there.
set -euo pipefail

ws=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused).name')
windows=$(i3-msg -t get_tree | jq --arg ws "$ws" \
    '[.. | select(.type? == "workspace" and .name == $ws) | .. | .window? | numbers] | length')

if [ "$windows" -gt 0 ]; then
    notify-send "Dev layout" "Workspace $ws isn't empty. Switch to an empty one first."
    exit 1
fi

i3-msg "append_layout ~/.config/i3/dev.json"
# Force new windows so each app fills its slot instead of reusing an open one
code --new-window &
firefox --new-window &
alacritty &
