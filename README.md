# dotfiles

Configuration repository for my Ubuntu home server, symlinked into place with
[Dotbot](https://github.com/anishathalye/dotbot) and bootstrapped by a handful
of setup scripts.

## What `./install` does

`./install` runs Dotbot with [`install.conf.yaml`](install.conf.yaml), which:

1. **Symlinks** configs into `$HOME` and `~/.config` (zsh, git, ssh, micro,
   yazi, bat, btop, zellij, superfile, …). rclone is the one exception — see
   [Setting up rclone](#setting-up-rclone).
2. **Installs zsh** and makes it the default shell (`chsh`).
3. Runs the setup scripts in order:
   - [`setup_ubuntu.zsh`](setup_ubuntu.zsh) — apt packages, Tailscale (exit node
     + subnet router), Rust via rustup, logind lid-switch tweaks, Samba.
   - [`setup_homebrew.zsh`](setup_homebrew.zsh) — installs Homebrew and everything
     in [`packages/Brewfile`](packages/Brewfile) (CLI tools **plus** the `uv` and
     `npm` packages — the Brewfile is the single source of truth for those).
   - [`setup_docker.zsh`](setup_docker.zsh) — Docker Engine, IPv6, and (if the
     private homelab repo is reachable over SSH) the container stack + AdGuard
     DNS bind.
   - [`setup_rclone.zsh`](setup_rclone.zsh) — renders `~/.config/rclone/rclone.conf`
     from a committed template plus the gitignored secret in the repo-root `.env`.

## Bootstrap a fresh Ubuntu server

```bash
# 1. Install git (everything else is handled by the setup scripts)
sudo apt-get update && sudo apt-get install -y git

# 2. Generate an SSH key and add the public key to GitHub
#    (Settings → SSH and GPG keys → New SSH key)
ssh-keygen -t ed25519 -C "abdullah.au@outlook.com"  # accept defaults / set a passphrase
cat ~/.ssh/id_ed25519.pub                           # copy this into GitHub

# 3. Verify the SSH connection to GitHub (expect a "successfully authenticated"
#    greeting; answer "yes" to trust the host key on first connect)
ssh -T git@github.com

# 4. Clone the repo over SSH (path is not important — scripts resolve their own
#    location)
git clone git@github.com:abdullahau/dotfiles.git ~/Developer/dotfiles
cd ~/Developer/dotfiles

# 5. Switch to the ubuntu branch (default branch is `main`; the Ubuntu server
#    config lives on `ubuntu`)
git checkout ubuntu

# 6. Provide local secrets (Tailscale auth key, etc.)
cp .env.example .env
$EDITOR .env          # fill in TAILSCALE_AUTH_KEY (leave blank to skip auto-up)

# 7. Run the installer (pulls the dotbot submodule, symlinks, runs setup scripts)
./install
```

Notes:

- `./install` is safe to re-run; symlinking and the system-file writes are
  idempotent.
- The **homelab** container stack (`setup_docker.zsh`) clones a **private** repo
  over SSH, so it reuses the GitHub SSH key set up in steps 2–3. If that key
  isn't in place, the step is skipped with a warning and can be finished by
  re-running `./install`.
- Switching to zsh takes effect on your next login; zsh4humans bootstraps itself
  on first interactive shell.

## Packages

- [`packages/Brewfile`](packages/Brewfile) — Homebrew formulae/casks + `uv` tools
  + `npm` packages. Refresh with `bbd` (alias) / `brew bundle dump --describe
  --force --file=./packages/Brewfile`.
- [`packages/apt-packages`](packages/apt-packages) — apt packages (one per line,
  `#` comments allowed).

## Setting up rclone

`rclone.conf` holds a live OneDrive OAuth token, so it is **not tracked** and
`~/.config/rclone` is **not symlinked** into this repo. Two reasons:

1. It is a credential, and this repo is public on GitHub.
2. rclone *rewrites* `rclone.conf` in place every time it refreshes the access
   token (roughly hourly during a sync). Symlinking the directory meant every
   refresh dirtied the working tree and re-staged the secret.

So the layout is:

| File | Tracked? | Where it ends up |
| --- | --- | --- |
| `rclone/rclone-filters.txt` | yes | symlinked to `~/.config/rclone/` |
| `rclone/rclone.conf.template` | yes (no secrets) | rendered |
| `.env` (repo root) | **no**, gitignored | substituted into the template |
| `~/.config/rclone/rclone.conf` | n/a | real file, owned by rclone |

The secret lives in the same repo-root `.env` that already holds
`TAILSCALE_AUTH_KEY` — one file to fill in on a fresh machine. Seed it and
render:

```bash
cp .env.example .env
$EDITOR .env                 # paste the token, or re-auth with `rclone config`
./setup_rclone.zsh           # renders ~/.config/rclone/rclone.conf (0600)
rclone lsd onedrive:         # verify
```

`.env` is a **bootstrap seed, not the source of truth**. After the first
render rclone rotates the token in the live file and `.env` goes stale — that is
expected. It only has to be fresh enough to authenticate once. `setup_rclone.zsh`
therefore never overwrites an existing `rclone.conf` unless you pass `--force`.

To re-seed `.env` from the current live token (e.g. before setting up another
machine), then replace the two `ONEDRIVE_*` lines in `.env` with the output:

```bash
./setup_rclone.zsh --export
```

If the seed ever goes too stale to refresh, re-authenticate with
`rclone config reconnect onedrive:` and export again.

## Running rclone in the background

Rclone is a command line program to manage files on cloud storage.

`rclone copy` - Copy files from source to dest, skipping already copied.
`rclone sync` - Make source and dest identical, modifying destination only.

Sync `/mnt/hdd/onedrive` with OneDrive (ignoring filtered files):

```bash
rclone sync onedrive: /mnt/hdd/onedrive \
  --filter-from ~/.config/rclone/rclone-filters.txt \
  --progress --stats 5s --stats-one-line -v
```

### Keep it running with `tmux`

```bash
# Create a detached session that runs the sync immediately
tmux new -d -s rclone 'rclone sync onedrive: /mnt/hdd/onedrive --filter-from ~/.config/rclone/rclone-filters.txt'

tmux ls                 # list sessions
tmux attach -t rclone   # re-attach (Ctrl+b then d to detach)
tmux kill-session -t rclone
```

The session persists across terminal close, SSH logout, and disconnects.

## Debug Docker context error

```bash
docker context ls              # inspect current context
docker context use default     # switch to the root daemon socket
docker version                 # verify

# Remove a leftover rootless context/config
docker context rm rootless 2>/dev/null
rm -rf ~/.config/docker ~/.local/share/docker
```
