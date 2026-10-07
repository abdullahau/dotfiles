#!/usr/bin/env sh

# No bar running yet means this is a fresh login: give i3 a moment to settle
# so the bar starts once, complete (workspace numbers included).
pgrep -u "$(id -u)" -x polybar >/dev/null || login=1

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -u "$(id -u)" -x polybar >/dev/null || break
  sleep 0.2
done
pkill -9 -u "$(id -u)" -x polybar 2>/dev/null

# At login i3 runs this before it has created workspace 1; wait (max 5s)
# so the workspace module doesn't start out empty.
for i in $(seq 25); do
  i3-msg -t get_workspaces 2>/dev/null | grep -q '"name"' && break
  sleep 0.2
done
echo "$(date +%T) i3 ready after $(( (i - 1) * 200 ))ms${login:+ (login)}" >>"${XDG_RUNTIME_DIR:-/tmp}/polybar-launch.log"
[ -n "$login" ] && sleep 1

# for multimonitor
if command -v xrandr >/dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload example >>"${XDG_RUNTIME_DIR:-/tmp}/polybar-$m.log" 2>&1 & disown
  done
else
  polybar --reload example >"${XDG_RUNTIME_DIR:-/tmp}/polybar.log" 2>&1 & disown
fi
