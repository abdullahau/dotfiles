# dotfiles — `main` branch

Config for my Macs. [Dotbot](https://github.com/anishathalye/dotbot) symlinks it;
the setup scripts bootstrap the rest.

Branches: `main` (this machine), `homelab` (Ubuntu home server), `vps`.

## Bootstrap

```bash
xcode-select --install                 # git + Homebrew prerequisite
git clone https://github.com/abdullahau/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install
```

`./install` is safe to re-run; the symlinks and `defaults` writes are idempotent.
zsh becomes the login shell at your next login. Clone path doesn't matter —
`install` resolves its own location.

## What `./install` runs

| Script | Does |
| --- | --- |
| `setup_homebrew.zsh` | Homebrew and everything in `packages/Brewfile`, Xcode license, share perms |
| `setup_zsh.zsh` | adds Homebrew's zsh to `/etc/shells` (sudo), then `chsh` to it |
| `setup_macos.zsh` | Finder, Dock, and Mission Control `defaults`, then restarts both |
| `setup_uv.zsh` | `uv tool install` for each entry in `packages/uv-tools` |

Dotbot links shell, git, ssh, ghostty, zed, micro, nano, yazi, bat, btop, atuin,
fastfetch, marimo, logseq, ruff, codebook, and Raycast scripts.

## Run by hand

```bash
./macos_deepcleaner.sh                                    # fd + fzf TUI, large files and caches
./honor-tablet/debloat.sh honor-tablet/packages-remove.txt  # adb debloat a tablet
```

Raycast settings are `.rayconfig` exports in `raycast/`, imported through Raycast
itself; only `raycast/scripts` is symlinked.

## Packages

- `packages/Brewfile` — formulae, casks, **and** VS Code extensions. Refresh with
  `brew bundle dump --describe --force --file=./packages/Brewfile`; the `bbd`
  alias omits `--describe --force`, so it drops comments and fails on an
  existing file.
- `packages/uv-tools` — one per line, `#` comments allowed.

## Notes

`cli-utils.md` (ImageMagick snippets), `ghostty/ghostty-shortcuts.md`
(keybindings), `honor-tablet/instruction.md` (adb setup).
