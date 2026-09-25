# Catppuccin Mocha, taken from the starship bar this box ran before p10k.
# Colours only. base.zsh owns the layout.
# Every pair clears 4.5:1. Run zsh/p10k/contrast.py after an edit.

() {
  local crust='#11111b' red='#f38ba8' peach='#fab387' yellow='#f9e2af'
  local green='#a6e3a1' mauve='#cba6f7' surface0='#313244'
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
  # Mauve, then cream, then dark. Grey sat outside the palette, and the
  # exec-time chip must not share a colour with user@host or p10k draws a
  # thin arc between them instead of a head.
  for s in STATUS_OK STATUS_OK_PIPE COMMAND_EXECUTION_TIME BACKGROUND_JOBS; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$mauve          # 9.23:1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$crust
  done
  # Every context state, including the REMOTE ones base.zsh declares through
  # brace expansion. Over SSH p10k uses CONTEXT_REMOTE, not CONTEXT.
  for s in CONTEXT CONTEXT_DEFAULT CONTEXT_REMOTE CONTEXT_REMOTE_SUDO CONTEXT_SUDO; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$yellow         # 14.76:1
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

  # --- git chip text ---
  # p10k does not take these from VCS_*_FOREGROUND. See base.zsh.
  typeset -g _p10k_git_meta="%F{$crust}"        # 14.76:1 on yellow
  typeset -g _p10k_git_clean="%F{$crust}"
  typeset -g _p10k_git_modified="%F{$crust}"
  typeset -g _p10k_git_untracked="%F{$crust}"
  typeset -g _p10k_git_conflicted='%F{#7d0b2b}'  # 8.45:1, still reads as red

  # --- every language and tool chip ---
  _p10k_tool_chips $yellow $crust
}
