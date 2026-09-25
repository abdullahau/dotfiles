# zsh

This box runs [zsh4humans](https://github.com/romkatv/zsh4humans) (z4h).

## Why z4h

z4h ships one tuned bundle instead of separate plugins:

- **powerlevel10k** prompt with **gitstatusd**, a resident daemon. Git status
  costs about 1 ms. Starship forked `git` at every prompt, which cost 24 ms in
  a 500-file repo.
- **Instant prompt.** The prompt paints in about 17 ms and buffers your keys
  while the rest loads.
- fzf, completions, autosuggestions, syntax highlighting and history search,
  all loaded in the right order and compiled to `.zwc`.

Do not install those parts through Homebrew. z4h keeps its own copies in
`~/.cache/zsh4humans/v5`.

## Files

| File | Links to | Purpose |
|---|---|---|
| `zshenv` | `~/.zshenv` | PATH for non-interactive shells, then the z4h bootstrap |
| `zshrc` | `~/.zshrc` | everything else |
| `p10k.zsh` | `~/.p10k.zsh` | prompt appearance |
| `inputrc` | `~/.inputrc` | readline, for non-zsh tools |
| `zfunc/` | `~/.zfunc` | hand-written completions |
| `backup/` | — | the old starship setup, kept for reference |

## Load order

`zshrc` has one hard rule. `z4h init` runs `compinit` inside it, so:

- **Before `z4h init`:** `fpath`, generated completion scripts, PATH.
- **After `z4h init`:** keybindings, aliases, functions, tool init.

atuin loads last, because it takes Ctrl+R and Up away from z4h's own history
search. That is deliberate. Remove the two `_cached_eval atuin` lines to get
z4h's inline search back.

## History

`setopt EXTENDED_HISTORY` matters. `SHARE_HISTORY` writes a timestamp on each
command, but a full file rewrite (every shell exit) reads `EXTENDED_HISTORY`
alone. Without it, every exit strips the timestamps off the older lines.
The timestamps cost 24 bytes a line and no measurable time.

## Caches

Tool init output is cached in `~/.cache/zsh/init` and rebuilt only when the
tool binary is newer. Run `zcache-clear` after you change a tool's config.

## Updating

Run `z4h update`. It asks every 7 days on its own.
