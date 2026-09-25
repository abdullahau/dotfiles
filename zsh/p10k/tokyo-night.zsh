# Tokyo Night. Hues from the starship bar in zsh/backup/starship, but the
# lightness is not: that preset puts #e3e5e5 on #769ff0, which is 2.08:1.
# Every pair below clears 4.5:1. Run zsh/p10k/contrast.py after an edit.

() {
  local ice='#a3aed2' blue='#769ff0' navy='#394260' ink='#1d2230'
  local dark='#090c0c' deep='#16161e' dim='#24283b'
  local fg='#c0caf5' fgdim='#a9b1d6' comment='#565f89'
  local green='#9ece6a' red='#f7768e' rederr='#1a1b26'

  # --- left bar ---
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=$ice          # 8.92:1
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$dark

  typeset -g POWERLEVEL9K_DIR_BACKGROUND=$blue             # 6.84:1
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$deep
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$dim    # 5.54:1, reads as secondary
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$deep
  local s
  for s in DIR_WORK DIR_WORK_NON_EXISTENT DIR_WORK_NOT_WRITABLE; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$blue
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$deep
  done

  for s in VCS_CLEAN VCS_MODIFIED VCS_UNTRACKED VCS_CONFLICTED; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$navy          # 6.13:1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$fg
  done
  typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND=$navy
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$fgdim    # 4.69:1

  # --- right bar ---
  for s in STATUS_OK STATUS_OK_PIPE COMMAND_EXECUTION_TIME CONTEXT BACKGROUND_JOBS; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$navy          # 6.13:1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$fg
  done
  for s in STATUS_ERROR STATUS_ERROR_PIPE STATUS_ERROR_SIGNAL CONTEXT_ROOT; do
    typeset -g POWERLEVEL9K_${s}_BACKGROUND=$red           # 6.46:1
    typeset -g POWERLEVEL9K_${s}_FOREGROUND=$rederr
  done
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=$ink             # 9.83:1
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$fg

  # --- line two ---
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$red

  # --- the gap between the two bars ---
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=$comment

  # --- git chip text ---
  # p10k does not take these from VCS_*_FOREGROUND. See base.zsh.
  typeset -g _p10k_git_meta="%F{$fg}"           # 6.13:1 on navy
  typeset -g _p10k_git_clean="%F{$fg}"
  typeset -g _p10k_git_modified="%F{$fg}"
  typeset -g _p10k_git_untracked="%F{$fg}"
  typeset -g _p10k_git_conflicted='%F{#ff9aa8}'  # 4.92:1, still reads as red

  # --- every language and tool chip ---
  _p10k_tool_chips $navy $fg
}
