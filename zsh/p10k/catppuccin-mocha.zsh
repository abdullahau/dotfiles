# Catppuccin Mocha, taken from the starship bar in zsh/backup/starship.
# Colours only. base.zsh owns the layout.
# Every pair clears 4.5:1. Run zsh/p10k/contrast.py after an edit.

() {
  local crust='#11111b' red='#f38ba8' peach='#fab387' yellow='#f9e2af'
  local green='#a6e3a1' overlay1='#7f849c' surface0='#313244'
  local surface1='#45475a' subtext0='#a6adc8' text='#cdd6f4'

  # --- left bar ---
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=$red
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$crust

  typeset -g POWERLEVEL9K_DIR_BACKGROUND=$peach
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$crust
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='#6b3410'  # 5.59:1
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
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$text      # 6.31:1

  # --- right bar ---
  for s in STATUS_OK STATUS_OK_PIPE COMMAND_EXECUTION_TIME CONTEXT BACKGROUND_JOBS; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$overlay1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  for s in STATUS_ERROR STATUS_ERROR_PIPE STATUS_ERROR_SIGNAL CONTEXT_ROOT; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$red
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  # overlay0 is a dead zone: crust scores 3.84 on it and text only 3.38.
  # A darker chip with light text keeps the right bar's grey-to-dark run.
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=$surface0        # 8.69:1
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$text

  # --- line two ---
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$red

  # --- the gap between the two bars ---
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=$surface1

  # --- every language and tool chip ---
  _p10k_tool_chips $yellow $crust
}
