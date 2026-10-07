#!/usr/bin/env python3
"""Super+? : list every i3 shortcut in rofi. Built from ~/.config/i3/config each
time, so it stays current. Pick a line to run that shortcut's action."""
import os, re, subprocess

CONF = os.path.expanduser("~/.config/i3/config")

# Friendly names for commands; first regex that matches wins.
DESCRIBE = [
    (r"powermenu", "Power menu (suspend, log out, reboot, shut down)"),
    (r"keyhelp", "This shortcut list"),
    (r"rofi -show calc", "Calculator"),
    (r"rofi -show drun", "App launcher (apps only)"),
    (r"rofi -show combi", "Launcher: apps + open windows"),
    (r"clipmenu", "Clipboard history"),
    (r"exec \$term -e yazi", "yazi file manager (terminal)"),
    (r"exec \$term$", "Terminal"),
    (r"exec firefox", "Firefox"),
    (r"exec thunar", "Thunar file manager"),
    (r"pavucontrol", "Volume control window"),
    (r"pamixer -ui", "Volume up"), (r"pamixer -ud", "Volume down"),
    (r"--default-source -t", "Microphone mute"), (r"pamixer -t", "Mute"),
    (r"brightnessctl .*\+5%", "Brightness up"), (r"brightnessctl .*5%-", "Brightness down"),
    (r"playerctl play-pause", "Play / pause"), (r"playerctl next", "Next track"),
    (r"playerctl previous", "Previous track"),
    (r"flameshot gui", "Screenshot: select area"), (r"flameshot full", "Screenshot: full screen to ~/Pictures"),
    (r"dunstctl history-pop", "Show last notification again"),
    (r"dunstctl close-all", "Clear all notifications"),
    (r"^kill$", "Close window"),
    (r"^focus (left|right|up|down)$", "Focus window \\1"),
    (r"^move (left|right|up|down)$", "Move window \\1"),
    (r"^workspace number \$ws(\d+)$", "Go to workspace \\1"),
    (r"^move container to workspace number \$ws(\d+)$", "Move window to workspace \\1"),
    (r"^workspace back_and_forth$", "Previous workspace"),
    (r"^split h$", "Next window opens beside"), (r"^split v$", "Next window opens below"),
    (r"^split toggle$", "Toggle split direction"),
    (r"^fullscreen toggle$", "Fullscreen"),
    (r"^layout stacking$", "Layout: stacked"), (r"^layout tabbed$", "Layout: tabbed"),
    (r"^layout toggle split$", "Layout: tiled (toggle direction)"),
    (r"^sticky toggle$", "Pin floating window on all workspaces"),
    (r"^floating toggle$", "Float / tile window"),
    (r"^focus mode_toggle$", "Switch focus floating / tiled"),
    (r"^focus parent$", "Select parent container"),
    (r"^move scratchpad$", "Hide window in scratchpad"),
    (r"^scratchpad show$", "Show scratchpad window"),
    (r"^reload$", "Reload i3 config"), (r"^restart$", "Restart i3"),
    (r'^mode "resize"$', "Resize mode (arrows resize, Enter/Esc exit)"),
]

def nice_key(k):
    k = k.replace("$mod", "Super").replace("Mod4", "Super").replace("Mod1", "Alt")
    k = k.replace("ctrl", "Ctrl").replace("Return", "Enter").replace("minus", "-")
    k = k.replace("slash", "/").replace("question", "?").replace("XF86Audio", "Media ").replace("XF86MonBrightness", "Brightness ")
    k = re.sub(r"Media (Raise|Lower)Volume", lambda m: "Volume " + ("up" if m[1] == "Raise" else "down") + " key", k)
    k = k.replace("Brightness Up", "Brightness up key").replace("Brightness Down", "Brightness down key")
    k = k.replace("Media MicMute", "Mic mute key").replace("Media Mute", "Mute key")
    k = k.replace("Media Play", "Play key").replace("Media Next", "Next key").replace("Media Prev", "Prev key")
    return k.replace("Print", "PrtSc")

def describe(cmd):
    c = re.sub(r"^exec (--no-startup-id )?", "exec ", cmd).strip().strip('"')
    bare = re.sub(r"^exec ", "", c)
    for pat, text in DESCRIBE:
        for cand in (c, bare, cmd):
            m = re.search(pat, cand)
            if m:
                return m.expand(text)
    return bare

rows, mode = [], None
for line in open(CONF):
    s = line.strip()
    if s.startswith("mode "):
        mode = s.split('"')[1]; continue
    if mode and s == "}":
        mode = None; continue
    if not s.startswith("bindsym ") or mode:
        continue
    parts = s.split(None, 2)
    if len(parts) < 3:
        continue
    key, cmd = parts[1], parts[2]
    rows.append((nice_key(key), describe(cmd), cmd))

# Shortcuts that aren't i3 bindsym lines (mouse, apps, bar, keyboard)
EXTRAS = [
    ("Super + drag", "Move floating window (right-drag resizes)"),
    ("Ctrl+Shift+c / v", "Terminal: copy / paste"),
    ("Ctrl+Shift+f", "Terminal: search scrollback"),
    ("Ctrl+= / - / 0", "Terminal: bigger / smaller / reset text"),
    ("Bar: click 1-10", "Switch to that workspace"),
    ("Bar: volume", "Scroll = change, click = mute, right-click = mixer"),
    ("Bar: brightness", "Scroll = change"),
    ("Bar: Bluetooth", "Click = manager, right-click = on/off"),
    ("Bar: Wi-Fi icon", "Click = networks menu"),
    ("Fn+Esc", "Fn lock: top row as F1-F12 or media keys"),
]

# Collapse the 10 per-workspace lines into one each
def collapse(rows, pat, label, keyfmt):
    hits = [r for r in rows if re.fullmatch(pat, r[1])]
    if len(hits) > 3:
        rows = [r for r in rows if r not in hits]
        rows.append((keyfmt, label, None))
    return rows
rows = collapse(rows, r"Go to workspace \d+", "Go to workspace 1-10", "Super+1..0")
rows = collapse(rows, r"Move window to workspace \d+", "Move window to workspace 1-10", "Super+Shift+1..0")

rows += [(k, d, None) for k, d in EXTRAS]
width = max(len(r[0]) for r in rows) + 2
lines = [f"{k.ljust(width)}{d}" for k, d, _ in rows]

out = subprocess.run(
    ["rofi", "-dmenu", "-i", "-p", "shortcuts", "-no-custom", "-format", "i",
     "-theme-str", "window {width: 760px;} listview {lines: 14;} mode-switcher {enabled: false;}"],
    input="\n".join(lines), capture_output=True, text=True)
if out.returncode == 0 and out.stdout.strip().isdigit():
    cmd = rows[int(out.stdout.strip())][2]
    if cmd:
        subprocess.run(["i3-msg", cmd], capture_output=True)
