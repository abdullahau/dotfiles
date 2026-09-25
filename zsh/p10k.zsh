# ~/.p10k.zsh — theme dispatcher.
#
# base.zsh holds the layout, icons and separators that `p10k configure`
# writes. The palette files next to it only change colours. `prompt-theme`
# picks one and writes the choice to a state file.
#
# After you run `p10k configure`, move the new ~/.p10k.zsh over
# zsh/p10k/base.zsh and restore this file. See zsh/README.md.

_p10k_dir=${${(%):-%x}:A:h}/p10k
_p10k_state=${XDG_STATE_HOME:-$HOME/.local/state}/zsh/prompt-theme
_p10k_default=catppuccin-mocha

# Paint every language and tool chip in one colour, the way the starship
# bars these palettes came from did. Call it from a palette file.
_p10k_tool_chips() {
  local bg=$1 fg=$2 p seg k skip
  # Segments the palettes colour by hand. These are glob patterns, not exact
  # names: p10k gives several of them extra state variants (CONTEXT_REMOTE,
  # STATUS_OK_PIPE, DIR_WORK_NOT_WRITABLE), some declared through brace
  # expansion. A state missed here gets painted as a tool chip, which is how
  # user@host ended up the same colour as the git chip.
  local -a keep=(
    OS_ICON  DIR  'DIR_*'  'VCS*'  'STATUS*'  'CONTEXT*'
    TIME  COMMAND_EXECUTION_TIME  BACKGROUND_JOBS
    'PROMPT_CHAR*'  'MULTILINE_*'  'VI_MODE*'
  )
  for p in ${(k)parameters[(I)POWERLEVEL9K_*_BACKGROUND]}; do
    seg=${${p#POWERLEVEL9K_}%_BACKGROUND}
    skip=0
    for k in $keep; do [[ $seg == ${~k} ]] && { skip=1; break } done
    (( skip )) && continue
    typeset -g $p=$bg
    typeset -g ${p%_BACKGROUND}_FOREGROUND=$fg
  done
}

# Hide the divider inside a run of same-coloured chips.
#
# When two neighbours share a background, p10k draws the thin subsegment arc
# instead of a head, and it paints that arc in the chip's own text colour.
# The palettes give whole groups one colour on purpose (status, exec time and
# background jobs; every tool chip), so that arc reads as a seam inside what
# should look like one chip. Paint each arc in its own chip's background.
#
# p10k re-appends the segment style after a separator that holds a '%', so the
# colour stops at the arc and does not leak into the chip's text.
# Leave the \u escapes alone: p10k expands them itself, the same way it does
# for the two globals in base.zsh.
_p10k_hide_subsep() {
  local p seg bg
  for p in ${(k)parameters[(I)POWERLEVEL9K_*_BACKGROUND]}; do
    bg=${(P)p}
    [[ -n $bg ]] || continue
    seg=${${p#POWERLEVEL9K_}%_BACKGROUND}
    typeset -g POWERLEVEL9K_${seg}_LEFT_SUBSEGMENT_SEPARATOR="%F{$bg}$POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR"
    typeset -g POWERLEVEL9K_${seg}_RIGHT_SUBSEGMENT_SEPARATOR="%F{$bg}$POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR"
  done
}

source $_p10k_dir/base.zsh

() {
  local theme=$_p10k_default
  [[ -r $_p10k_state ]] && read -r theme < $_p10k_state
  [[ -r $_p10k_dir/$theme.zsh ]] || theme=$_p10k_default
  source $_p10k_dir/$theme.zsh
}

# After the palette, so every chip's background is final.
_p10k_hide_subsep
