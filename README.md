# dotfiles — `homelab` branch

Config for my Ubuntu home server. [Dotbot](https://github.com/anishathalye/dotbot)
symlinks it; the setup scripts bootstrap the rest.

Branches: `main` (macOS), `homelab` (this server), `vps`.

## Bootstrap

```bash
sudo apt-get update && sudo apt-get install -y git
ssh-keygen -t ed25519 -C "abdullah.au@outlook.com"    # add the .pub key to GitHub
git clone git@github.com:abdullahau/dotfiles.git ~/Developer/dotfiles
cd ~/Developer/dotfiles && git checkout homelab
cp .env.example .env && $EDITOR .env                  # TAILSCALE_AUTH_KEY, ONEDRIVE_*
./install
```

`./install` is safe to re-run. zsh becomes the default shell at your next login.

## What `./install` runs

| Script | Does |
| --- | --- |
| `setup_ubuntu.zsh` | apt packages, Tailscale (exit node + subnet router), Rust, lid-switch, Samba |
| `setup_homebrew.zsh` | Homebrew and everything in `packages/Brewfile` |
| `setup_docker.zsh` | Docker Engine, IPv6, `/data` dirs, clones the private homelab repo, AdGuard DNS bind |
| `setup_rclone.zsh` | renders `~/.config/rclone/rclone.conf` |

The homelab clone needs the GitHub SSH key. Without it that step is skipped —
re-run `./install` once the key is in place.

## Run by hand

```bash
sudo ./setup_hdd_docker_mount.zsh UUID=<uuid>   # mount /mnt/hdd, restart bound containers on remount
./setup_tailscale_serve.zsh                     # router admin on the tailnet at :8443
./setup_bbr.sh                                  # TCP BBR + fq pacing
```

## Packages

- `packages/Brewfile` — formulae, casks, `uv` tools, `npm` packages. Refresh with `bbd`.
- `packages/apt-packages` — one per line, `#` comments allowed.

## rclone

`rclone.conf` holds a live OneDrive token, so it is gitignored and
`~/.config/rclone` is a real directory, not a symlink. `.env` seeds it once;
rclone owns the file after that.

```bash
./setup_rclone.zsh            # render, only if missing
./setup_rclone.zsh --force    # re-render from .env
./setup_rclone.zsh --export   # print the live token as .env lines
rclone sync onedrive: /mnt/hdd/onedrive --filter-from ~/.config/rclone/rclone-filters.txt --progress
```

## Fix a broken Docker context

```bash
docker context use default
docker context rm rootless 2>/dev/null
rm -rf ~/.config/docker ~/.local/share/docker
```
