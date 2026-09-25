# Tokyo Night, taken from the starship bar in zsh/backup/starship.
# Colours only. base.zsh owns the layout.

() {
  local ice='#a3aed2' blue='#769ff0' navy='#394260' ink='#1d2230'
  local dark='#090c0c' light='#e3e5e5'
  local green='#9ece6a' red='#f7768e' dim='#565f89'

  # --- left bar ---
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=$ice
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$dark

  typeset -g POWERLEVEL9K_DIR_BACKGROUND=$blue
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$light
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='#2b3f63'
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND='#ffffff'
  local s
  for s in DIR_WORK DIR_WORK_NON_EXISTENT DIR_WORK_NOT_WRITABLE; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$blue
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$light
  done

  for s in VCS_CLEAN VCS_MODIFIED VCS_UNTRACKED VCS_CONFLICTED; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$navy
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$blue
  done
  typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND=$navy
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$dim

  # --- right bar ---
  for s in STATUS_OK STATUS_OK_PIPE COMMAND_EXECUTION_TIME CONTEXT BACKGROUND_JOBS; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$navy
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$blue
  done
  for s in STATUS_ERROR STATUS_ERROR_PIPE STATUS_ERROR_SIGNAL CONTEXT_ROOT; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$red
    typeset -g POWERLEVEL9K_${s}_FOREGROUND='#1a1b26'
  done
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=$ink
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$blue

  # --- line two ---
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$red

  # --- the gap between the two bars ---
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=$dim

  # --- every language and tool chip ---
  _p10k_tool_chips $navy $blue
}
