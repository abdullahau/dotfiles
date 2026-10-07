source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Fit fastfetch to the window: i3 resizes new terminals right after they
# open, so wait a moment, then pick a layout that fits the real width.
function fish_greeting
    sleep 0.05
    set -l cols (tput cols)
    if test $cols -ge 112
        fastfetch
    else if test $cols -ge 82
        fastfetch --logo small
    else
        fastfetch --logo none
    end
end
