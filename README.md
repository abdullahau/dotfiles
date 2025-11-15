# dotfiles

Configuration repository containing my customized home folder dotfiles.

## Steps to bootstrap a new Ubuntu Server

1. Install Apple's Command Line Tools, which are prerequisites for Git and Homebrew.

```zsh
xcode-select --install
```


2. Clone repo into new hidden directory.

```zsh
# Use SSH (if set up)...
git clone git@github.com:eieioxyz/Beyond-Dotfiles-in-100-Seconds.git ~/.dotfiles

# ...or use HTTPS and switch remotes later.
git clone https://github.com/eieioxyz/Beyond-Dotfiles-in-100-Seconds.git ~/.dotfiles
```


3. Create symlinks in the Home directory to the real files in the repo.

```zsh
# There are better and less manual ways to do this;
# investigate install scripts and bootstrapping tools.

ln -s ~/.dotfiles/.zshrc ~/.zshrc
ln -s ~/.dotfiles/.gitconfig ~/.gitconfig
```


4. Install Homebrew, followed by the software listed in the Brewfile.

```zsh
# These could also be in an install script.

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then pass in the Brewfile location...
brew bundle --file ~/.dotfiles/Brewfile

# ...or move to the directory first.
cd ~/.dotfiles && brew bundle
```

## Running rclone in the background

### Simple background process

```bash
nohup rclone sync onedrive: /path/to/local/folder > rclone.log -filter-from /path/to/rclone-filter.txt 2>&1 &
```

### Using `tmux` 

**Create and run the tmux session:**

```bash
# Start a new named tmux session
tmux new -s rclone

# From inside the tmux session - run your command
rclone sync onedrive: /mnt/hdd/onedrive --filter-from ~/.config/rclone/rclone-filters.txt
```

**Detach (leave it running in background):**

While inside the tmux session, press:

```
Ctrl+b, then d
```
(Press Ctrl+b, release, then press d)

This detaches you from the session but the process keeps running.

**Re-attach (come back to check on it):**

```bash
tmux attach -t rclone
# or shorthand:
tmux a -t rclone
```

**One-liner to create detached session:**

```bash
# Create detached session and run command immediately
tmux new -d -s rclone 'rclone sync onedrive: /mnt/hdd/onedrive --filter-from ~/.config/rclone/rclone-filters.txt'
```

**Useful tmux commands:**

```bash
# List all sessions
tmux ls

# Kill the session when done
tmux kill-session -t rclone

# Attach to last session (if you forgot the name)
tmux attach
```

**Check if it's still running:**

```bash
tmux ls  # Will show [session_name] if running
```

The session persists even if you:
- Close your terminal
- Log out of SSH
- Disconnect from the server

## Debug Docker context error

```bash
# 1. Check your current context
docker context ls

# 2. Switch to the default (root daemon) context
docker context use default

# 3. Verify it's now using the correct socket
docker context ls

# 4. Test
docker version

# Remove rootless context
docker context rm rootless 2>/dev/null

# Clean up any remaining rootless config
rm -rf ~/.config/docker
rm -rf ~/.local/share/docker
```

## TODO 
- Terminal Preferences
- Change Shell to ZSH
- Dock Preferences
- Mission Control Preference (Don't Rearrange Spaces)
- Finder Show Path Bar and Set to Column View
- .zshrc
- Git (config and SSH)
- uv tool installation automation (ruff, pyrefly, basedpyright, jupyterlab, jupyter-core)
- Linux pacman / yay package manager automation
- Streamline completions from uv, uvx, ruff, docker, & tailscale
- what is an fpath? How is this related to shell autocompletions? What is an ideal way to source package completion files in ZSH
- AdGuard Home upstream DNS servers (Cloudflare, Quad9, Google, Etisalat)

## TODO List

- Learn how to use [`defaults`](https://macos-defaults.com/#%F0%9F%99%8B-what-s-a-defaults-command) to record and restore System Preferences and other macOS configurations.
- Organize these growing steps into multiple script files.
- Automate symlinking and run script files with a bootstrapping tool like [Dotbot](https://github.com/anishathalye/dotbot).
- Revisit the list in [`.zshrc`](.zshrc) to customize the shell.
- Make a checklist of steps to decommission your computer before wiping your hard drive.
- Create a [bootable USB installer for macOS](https://support.apple.com/en-us/HT201372).
- Integrate other cloud services into your Dotfiles process (Dropbox, Google Drive, etc.).
- Find inspiration and examples in other Dotfiles repositories at [dotfiles.github.io](https://dotfiles.github.io/).
- And last, but hopefully not least, [**take my course, *Dotfiles from Start to Finish-ish***](https://www.udemy.com/course/dotfiles-from-start-to-finish-ish/?referralCode=445BE0B541C48FE85276 "Learn Dotfiles from Start to Finish-ish on Udemy"
)!
