# zsh-next — the z4h-free config

A parallel zsh config for testing. It does not touch the live shell.
z4h stays in place until this config proves itself on all three machines.

## Try it

```sh
ZDOTDIR=~/.config/zsh-next zsh
```

Type `exit` to return to the z4h shell.

## What replaces what

| z4h gave us | Now |
| --- | --- |
| powerlevel10k | starship, `starship.toml` |
| gitstatus daemon | starship's own git code |
| zsh-autosuggestions | brew package |
| zsh-syntax-highlighting | brew package |
| zsh-completions | brew package |
| zsh-history-substring-search | atuin |
| fzf install and Ctrl+T | brew fzf, `fzf --zsh` |
| fzf tab completion | fzf-tab, cloned on first run |
| `z4h bindkey` layer | plain `bindkey` lines |
| `z4h-cd-back` and friends | the `_dirhist_*` widgets |
| compinit and its zstyles | written out in full |
| ohmyzsh | dropped. We never loaded anything from it |
| `z4h update` | `brew upgrade` |

## What we lose

1. **SSH teleport.** `z4h ssh` copied the config to a remote host. Nothing
   replaces it. The old config had it turned off, so this costs us nothing.
2. **Instant prompt.** p10k drew a prompt before the config finished loading.
   Startup is now 70 ms against z4h's 210 ms, so there is nothing to hide.
3. **gitstatus.** starship shells out to git. Very large repos may feel slower.

## Caching

Tool init output and generated completions are cached under
`~/.cache/zsh/`. They rebuild when a tool binary is newer. This is the
whole reason startup is 70 ms. After you change a tool's config, run:

```sh
zcache-clear
```

## Load order

Do not reorder these:

1. `fpath` additions, then `compinit`
2. `fzf-tab` (needs compinit)
3. tool init: fzf, then atuin, which takes Ctrl+R from fzf
4. `zsh-autosuggestions`
5. `zsh-syntax-highlighting` last. It wraps every other widget.

## Still to do

- [ ] Test on the macbook (check the `mac` keyboard bindings).
- [ ] Test on both Oracle VPS hosts.
- [ ] Confirm Shift+Arrow sequences in Ghostty, tmux and zellij.
- [ ] Decide whether to keep `alias cd=z`.
- [ ] Move `~/.zshenv` to a two-line stub that sets `ZDOTDIR`.
