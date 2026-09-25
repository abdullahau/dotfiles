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
  local bg=$1 fg=$2 p
  local -a keep=(
    OS_ICON DIR DIR_WORK DIR_WORK_NON_EXISTENT DIR_WORK_NOT_WRITABLE
    VCS_CLEAN VCS_MODIFIED VCS_UNTRACKED VCS_CONFLICTED VCS_LOADING
    STATUS_OK STATUS_OK_PIPE STATUS_ERROR STATUS_ERROR_PIPE STATUS_ERROR_SIGNAL
    COMMAND_EXECUTION_TIME CONTEXT CONTEXT_ROOT TIME BACKGROUND_JOBS
    PROMPT_CHAR MULTILINE_FIRST_PROMPT_GAP MULTILINE_NEWLINE_PROMPT_GAP
    VI_MODE_NORMAL VI_MODE_VISUAL VI_MODE_OVERWRITE
  )
  for p in ${(k)parameters[(I)POWERLEVEL9K_*_BACKGROUND]}; do
    (( ${keep[(Ie)${${p#POWERLEVEL9K_}%_BACKGROUND}]} )) && continue
    typeset -g $p=$bg
    typeset -g ${p%_BACKGROUND}_FOREGROUND=$fg
  done
}

source $_p10k_dir/base.zsh

() {
  local theme=$_p10k_default
  [[ -r $_p10k_state ]] && read -r theme < $_p10k_state
  [[ -r $_p10k_dir/$theme.zsh ]] || theme=$_p10k_default
  source $_p10k_dir/$theme.zsh
}
