#!/usr/bin/env zsh
# prompt-lab — try starship prompts without touching your config.
#
#   ./prompt-lab.zsh list              # what presets exist
#   ./prompt-lab.zsh show <name|file>  # render one across six scenarios
#   ./prompt-lab.zsh compare           # render every preset, one scenario
#   ./prompt-lab.zsh try <name|file>   # open a shell using it
#   ./prompt-lab.zsh save <name>       # copy a preset to starship.toml
#
# "mine" means the starship.toml next to this script.

emulate -L zsh
setopt err_return pipe_fail

local here=${0:A:h}
local lab=${TMPDIR:-/tmp}/prompt-lab
mkdir -p $lab

# Resolve a name to a config file. A preset name, a path, or "mine".
_resolve() {
  local n=$1
  [[ $n == mine ]] && { print -r -- $here/starship.toml; return }
  [[ -f $n ]] && { print -r -- ${n:A}; return }
  local f=$lab/preset-$n.toml
  [[ -f $f ]] || starship preset $n > $f 2>/dev/null || {
    print -u2 "unknown preset or file: $n"; return 1 }
  print -r -- $f
}

# Build the fixtures the scenarios run in. Costs a moment, then caches.
_fixtures() {
  [[ -d $lab/dirty/.git ]] && return
  rm -rf $lab/clean $lab/dirty $lab/plain
  mkdir -p $lab/clean $lab/dirty $lab/plain/deep/nested/path
  local d
  for d in clean dirty; do
    git -C $lab/$d init -q -b main
    print hello > $lab/$d/README.md
    git -C $lab/$d add -A
    git -C $lab/$d -c user.email=x@y -c user.name=x commit -qm init
  done
  print changed >> $lab/dirty/README.md
  print new > $lab/dirty/untracked.txt
}

# One prompt render. $1 config, $2 dir, rest passed to `starship prompt`.
_render() {
  local cfg=$1 dir=$2; shift 2
  ( builtin cd $dir && STARSHIP_CONFIG=$cfg starship prompt --terminal-width=100 "$@" )
}

_show() {
  local cfg=$1 label=$2
  _fixtures
  print -P "\n%F{6}%B── $label ──%b%f"
  local -a scenes=(
    'clean repo'        "$lab/clean"  '--status=0'
    'dirty repo'        "$lab/dirty"  '--status=0'
    'command failed'    "$lab/dirty"  '--status=1'
    'slow command'      "$lab/clean"  '--status=0 --cmd-duration=45000'
    'plain directory'   "$lab/plain"  '--status=0'
    'nested directory'  "$lab/plain/deep/nested/path" '--status=0'
  )
  local i
  for (( i = 1; i <= $#scenes; i += 3 )); do
    print -P "%F{8}${scenes[i]}%f"
    _render $cfg ${scenes[i+1]} ${(z)scenes[i+2]}
    print
  done
}

case ${1:-} in
  list)
    print -P "%BPresets%b"
    starship preset --list | sed 's/^/  /'
    print -P "\n%BYours%b\n  mine  ($here/starship.toml)"
    ;;
  show)
    [[ -n ${2:-} ]] || { print -u2 "usage: prompt-lab.zsh show <name|file|mine>"; exit 1 }
    _show "$(_resolve $2)" "$2"
    ;;
  compare)
    _fixtures
    for p in mine ${(f)"$(starship preset --list)"}; do
      cfg=$(_resolve $p) || continue
      print -P "\n%F{6}%B── $p ──%b%f"
      _render $cfg $lab/dirty --status=1 --cmd-duration=45000
    done
    print
    ;;
  try)
    [[ -n ${2:-} ]] || { print -u2 "usage: prompt-lab.zsh try <name|file|mine>"; exit 1 }
    cfg=$(_resolve $2)
    print -P "%F{8}starship config: $cfg — type exit to leave%f"
    STARSHIP_CONFIG=$cfg ZDOTDIR=$HOME/.config/zsh-next zsh
    ;;
  save)
    [[ -n ${2:-} ]] || { print -u2 "usage: prompt-lab.zsh save <name|file>"; exit 1 }
    cfg=$(_resolve $2)
    cp $here/starship.toml $here/starship.toml.bak
    cp $cfg $here/starship.toml
    print "saved $2 to starship.toml (old one kept as starship.toml.bak)"
    ;;
  *)
    sed -n '2,10p' ${0:A} | sed 's/^# \?//'
    ;;
esac
