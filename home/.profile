# Session environment. Loaded by ~/.xinitrc (fish does not read this file).
export BROWSER=firefox
export EDITOR=/usr/bin/vim
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"

# Qt apps: colours/icons/fonts from the GTK settings, Catppuccin via Kvantum
export QT_QPA_PLATFORMTHEME=gtk3
export QT_STYLE_OVERRIDE=kvantum

# Telemetry opt-outs for command-line tools that honour them
export DO_NOT_TRACK=1
export DISABLE_TELEMETRY=1          # Claude Code usage metrics
export DISABLE_ERROR_REPORTING=1    # Claude Code crash reports
