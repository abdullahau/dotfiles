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
| `p10k.zsh` | `~/.p10k.zsh` | theme dispatcher: sources the base, then a palette |
| `p10k/base.zsh` | — | prompt layout, icons and separators |
| `p10k/*.zsh` | — | one palette each, colours only |
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

## Prompt themes

Two palettes ship: `catppuccin-mocha` and `tokyo-night`. Both come from the
starship bars in `backup/starship`.

```
prompt-theme                  # show the current one and the list
prompt-theme tokyo-night      # switch, now and in every new shell
```

The choice goes to `~/.local/state/zsh/prompt-theme`, one word. Startup reads
that line and sources the matching palette. No subprocess.

`base.zsh` holds the layout. A palette file only sets colours, so a palette
survives a layout change. `_p10k_tool_chips` in `p10k.zsh` paints every
language and tool segment in one colour, the way the starship bars did, so a
new segment picks up the palette without an edit.

### After `p10k configure`

The wizard overwrites `~/.p10k.zsh`, which is the dispatcher. Put it back:

```
mv ~/.p10k.zsh zsh/p10k/base.zsh     # keep the new layout
git checkout zsh/p10k.zsh            # restore the dispatcher
./install                            # relink
```

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
