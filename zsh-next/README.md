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
   At 135 ms there is little left to hide. See the numbers below.
3. **gitstatus.** starship shells out to git. Very large repos may feel slower.

## Speed

Time from spawn to a drawn prompt, measured over a pty, five runs each:

| config | time |
| --- | --- |
| z4h, before the cache | 375 ms |
| z4h, with the cache | 180 ms |
| zsh-next with starship | 135 ms |

Measure it with `zsh -i -c exit` and you get much smaller numbers. Ignore
them. That never starts the line editor, and z4h defers p10k and compinit
until it does.

## Caching

Tool init output and generated completions are cached under `~/.cache/zsh/`.
They rebuild when a tool binary is newer.

`uv generate-shell-completion zsh` emits **565 KB** of zsh. Building it costs
26 ms, but parsing it costs far more. The cache is precompiled with `zcompile`,
so the parse goes away too. This is most of the speed above.

After you change a tool's config, run:

```sh
zcache-clear
```

The same cache and the same `zcache-clear` now exist in the z4h config, so
both shells behave the same way.

## Load order

Do not reorder these:

1. `fpath` additions, then `compinit`
2. `fzf-tab` (needs compinit)
3. tool init: fzf, then atuin, which takes Ctrl+R from fzf
4. `zsh-autosuggestions`
5. `zsh-syntax-highlighting` last. It wraps every other widget.

## Choosing a different prompt

`prompt-lab.zsh` renders prompts without touching your config:

```sh
./prompt-lab.zsh list            # the 12 built-in presets, plus "mine"
./prompt-lab.zsh compare         # every preset, same scenario, one screen
./prompt-lab.zsh show tokyo-night  # one prompt across six scenarios
./prompt-lab.zsh try  tokyo-night  # a real shell using it; exit to leave
./prompt-lab.zsh save tokyo-night  # overwrite starship.toml, keep a .bak
```

`show` renders six cases: clean repo, dirty repo, failed command, slow
command, plain directory, deep directory. Those are where prompts break.

`no-nerd-font`, `no-empty-icons` and `no-runtime-versions` are modifier
presets. They change parts of a config rather than replace it, so alone they
all look the same.

### Editing by hand

starship is one TOML file. Two ideas cover most of it:

- `format` is a template. `$git_branch` pulls in the `[git_branch]` module.
- Each module has its own `format`, which is a template over that module's
  variables.

Text wrapped in `( )` disappears when every variable inside it is empty. Skip
those brackets and a clean repo draws an empty coloured box.

Useful commands:

```sh
starship explain        # what each segment in the current prompt is
starship timings        # which module is slow
starship module git_status   # render one module alone
starship print-config   # config after defaults are filled in
starship toggle git_status   # turn a module off for this session
```

The module list is at <https://starship.rs/config/>.

## Still to do

- [ ] Test on the macbook (check the `mac` keyboard bindings).
- [ ] Test on both Oracle VPS hosts.
- [ ] Confirm Shift+Arrow sequences in Ghostty, tmux and zellij.
- [ ] Decide whether to keep `alias cd=z`.
- [ ] Move `~/.zshenv` to a two-line stub that sets `ZDOTDIR`.
