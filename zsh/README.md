# zsh

The shell config: plain zsh, starship for the prompt, plugins from Homebrew.
zsh4humans is gone, along with powerlevel10k.

## What this replaced

zsh4humans used to supply all of this:

| z4h gave us | now |
| --- | --- |
| powerlevel10k | starship, `starship/*.toml` |
| gitstatus daemon | starship's own git code |
| zsh-autosuggestions | brew package |
| zsh-syntax-highlighting | brew package |
| zsh-completions | brew package |
| zsh-history-substring-search | atuin |
| fzf install and Ctrl+T | brew fzf, `fzf --zsh` |
| fzf tab completion | fzf-tab, a submodule under `plugins/` |
| `z4h bindkey` layer | plain `bindkey` lines |
| `z4h-cd-back` and friends | the `_dirhist_*` widgets |
| compinit and its zstyles | written out in full |
| ohmyzsh | dropped. We never loaded a file from it |
| `z4h update` | `brew upgrade` |

## What went with it

1. **SSH teleport.** `z4h ssh` copied the config to a remote host. Nothing
   replaces it. The old config had it turned off, so it cost us nothing.
2. **Instant prompt.** p10k drew a prompt before the config finished loading.
   At ~93 ms there is little left to hide.
3. **gitstatus.** starship shells out to git, with a 1 s ceiling set in each
   theme. Very large repos may feel slower.

## Speed

Time from spawn to a drawn prompt, measured over a pty, five runs each:

| config | time |
| --- | --- |
| z4h, as it was | 375 ms |
| z4h, once its tool init was cached | ~172 ms |
| this config | ~93 ms |

The last two rows were measured back to back under the same load. Take single
readings with a pinch of salt: the same config has come in anywhere from 50 ms
to 95 ms depending on what else the machine was doing.

Measure with `zsh -i -c exit` and you get much smaller numbers. Ignore them.
That never starts the line editor, and z4h defers p10k and compinit until it
does.

Most of the gap over the earlier 135 ms came from `skip_global_compinit` in
`.zshenv`. Ubuntu's `/etc/zsh/zshrc` runs its own `compinit` before `~/.zshrc`
is read, so every shell paid for it twice.

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

The `homelab` branch carries the same cache in its own zsh config.

## Load order

Do not reorder these:

1. `fpath` additions, then `compinit`
2. `fzf-tab` (needs compinit)
3. tool init: fzf, then atuin, which takes Ctrl+R from fzf
4. `zsh-autosuggestions`
5. `zsh-syntax-highlighting` last. It wraps every other widget.

## Themes

Two themes live in `starship/`, both modified from the shipped presets:

- `catppuccin-powerline` — the default
- `tokyo-night`

Both carry the same changes:

- **Right side:** exit code, run time, user@host, clock.
- **Left side:** the preset as it ships, minus username and time, which moved
  right.
- **Input on line two**, which tokyo-night already did and catppuccin did not.
  catppuccin ships `[line_break] disabled = true`.
- `os` and `directory` stay chained, because both always render. Everything
  after them is a self-contained pill. The presets chain every segment, which
  leaves a trail of empty chevrons whenever a segment has nothing to show —
  visible in any directory that is not a git repo.

Switch with `prompt-theme`, which takes effect on the next prompt:

```sh
prompt-theme              # what is set, and what else exists
prompt-theme tokyo-night
```

The choice is one line in `~/.local/state/zsh/prompt-theme`, so a new shell
reads it without running anything.

## Where the plugins live

Everything comes from Homebrew except one:

| thing | source | path |
| --- | --- | --- |
| starship | brew | `$HOMEBREW_PREFIX/bin/starship` |
| zsh-autosuggestions | brew | `$HOMEBREW_PREFIX/share/zsh-autosuggestions/` |
| zsh-syntax-highlighting | brew | `$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/` |
| zsh-completions | brew | `$HOMEBREW_PREFIX/share/zsh-completions/` |
| fzf, atuin, zoxide | brew | `$HOMEBREW_PREFIX/bin/` |
| **fzf-tab** | **git submodule** | `zsh/plugins/fzf-tab` |

The brew ones are in `packages/Brewfile`, so `brew bundle` installs them.

fzf-tab has no Homebrew formula, so this repo carries it as a submodule.
dotbot links `zsh/plugins` to `~/.local/share/zsh/plugins`.

`submodule.recurse = true` is set in `git/gitconfig`, so a plain `git pull`
already checks out each submodule at the commit this repo pins. Nothing extra
to run on a new machine, and `./install` runs `git submodule update --init
--recursive` first anyway.

A submodule pins a commit. That is the point: every machine gets the same
fzf-tab. To move the pin to upstream's newest, once, on one machine:

```sh
git submodule update --remote --merge
git commit -am "bump zsh plugins"
```

Every other machine then picks it up on its next `git pull`.

## Choosing a different prompt

`prompt-lab.zsh` renders prompts without touching your config:

```sh
./prompt-lab.zsh list            # the 12 built-in presets, plus "mine"
./prompt-lab.zsh compare         # every preset, same scenario, one screen
./prompt-lab.zsh show tokyo-night  # one prompt across six scenarios
./prompt-lab.zsh try  tokyo-night  # a real shell using it; exit to leave
./prompt-lab.zsh add  gruvbox-rainbow  # keep a preset as one of your themes
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
