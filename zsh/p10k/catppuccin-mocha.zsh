# Catppuccin Mocha, taken from the starship bar in zsh/backup/starship.
# Colours only. base.zsh owns the layout.

() {
  local crust='#11111b' red='#f38ba8' peach='#fab387' yellow='#f9e2af'
  local green='#a6e3a1' overlay1='#7f849c' overlay0='#6c7086'
  local surface1='#45475a' subtext0='#a6adc8'

  # --- left bar ---
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=$red
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$crust

  typeset -g POWERLEVEL9K_DIR_BACKGROUND=$peach
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$crust
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='#8a5524'
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$crust
  local s
  for s in DIR_WORK DIR_WORK_NON_EXISTENT DIR_WORK_NOT_WRITABLE; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$peach
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done

  for s in VCS_CLEAN VCS_MODIFIED VCS_UNTRACKED VCS_CONFLICTED; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$yellow
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND=$surface1
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$subtext0

  # --- right bar ---
  for s in STATUS_OK STATUS_OK_PIPE COMMAND_EXECUTION_TIME CONTEXT BACKGROUND_JOBS; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$overlay1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  for s in STATUS_ERROR STATUS_ERROR_PIPE STATUS_ERROR_SIGNAL CONTEXT_ROOT; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$red
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=$overlay0
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$crust

  # --- line two ---
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$red

  # --- the gap between the two bars ---
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=$surface1

  # --- every language and tool chip ---
  _p10k_tool_chips $yellow $crust
}
