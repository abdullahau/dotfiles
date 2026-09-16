# Nix and NixOS starter

A starter config to move this setup to Nix. It is **not in use yet**. Nothing in the repo depends on it.

Status:

- The option and package names match nixpkgs 26.05 (checked on 2026-09-16).
- Nobody has run `nix flake check` on it yet. Expect small errors on the first build.
- The hardware values come from the current `homelab` box (MacBookPro12,1). Change them for a different machine.

## Contents

```
nix/
├── flake.nix                      # inputs + two outputs
├── home/
│   ├── default.nix                # dotfile links (replaces dotbot) + atuin service
│   └── packages.nix               # Brewfile → nixpkgs
├── hosts/homelab/
│   ├── default.nix                # user, SSH, mosh, lid switch, GPU, nix gc, sops
│   ├── disko.nix                  # disk layout for nixos-anywhere (WIPES the disk)
│   └── hardware-configuration.nix # placeholder, generated at install
├── modules/
│   ├── networking.nix             # Tailscale, BBR, UDP GRO, tailscale serve, firewall
│   ├── storage.nix                # /mnt/hdd, /data folders, Samba
│   └── containers.nix             # Docker + AdGuard, Glance, Transmission, Jellyfin
├── .sops.yaml                     # which age keys can decrypt secrets
└── secrets/secrets.example.yaml   # the secret names, no values
```

The flake has two outputs:

| Output | Use | Command |
| --- | --- | --- |
| `homeConfigurations.abdullah` | home-manager on any Linux distro (for example, Ubuntu) | `home-manager switch --flake ./nix#abdullah` |
| `nixosConfigurations.homelab` | a full NixOS install | `nixos-rebuild switch --flake ./nix#homelab` |

Both outputs load the same `home/` module.

## Background

### NixOS as a server

- NixOS has no separate server edition. Use the **minimal ISO**, which has no GUI.
- At runtime, NixOS is as fast as Ubuntu Server. It uses the same kernel, Docker, and binaries. Idle RAM is often lower, because it has no snapd.
- The costs come at build time:
  - `nixos-rebuild` uses 1–2 GB of RAM for a short time.
  - The binary cache supplies almost all packages. A custom kernel or a package override compiles, which is slow on old CPUs.
  - Old generations fill `/nix/store`. `nix.gc` and `auto-optimise-store` in `hosts/homelab/default.nix` clean it up.
- You can roll back a bad update from the boot menu.

### What Nix does not cover

- **Data.** `/data`, `/mnt/hdd`, and `/docker/*` (Plex database, Jellyfin metadata) still need backups.
- **Image tags.** `:latest` images are not reproducible. Pin tags or digests.
- **Samba passwords.** Run `sudo smbpasswd -a <user>` by hand.
- **z4h.** z4h downloads itself on first login. Nix does not manage it.

### Design choices

- **z4h keeps control of zsh.** `programs.zsh` stays off in home-manager, because it writes its own `.zshrc`. Home-manager only links the files in `zsh/`.
- **Links go to the repo, not to `/nix/store`.** `mkOutOfStoreSymlink` works like dotbot, so a config edit takes effect with no rebuild. `home/default.nix` expects the repo at `~/Developer/dotfiles`.
- **uid and gid stay at 1000.** `PUID`, `PGID`, and the file owners on the HDD still match.
- **`RequiresMountsFor = /mnt/hdd`** on the Jellyfin and Transmission units replaces `setup_hdd_docker_mount.zsh`.
- **Secrets use sops-nix.** The encrypted file lives in git. The host SSH key decrypts it at boot. Templates build the `.env` files outside `/nix/store`, readable only by root.
- **The firewall is on.** NixOS turns it on by default, but Ubuntu does not. Docker-published ports skip the firewall. Only host-network services (AdGuard, Samba, mosh) need entries.
- **`programs.nix-ld`** lets uv's Python builds and z4h's downloaded binaries run.

### Map from the old setup

| Old setup | Nix file |
| --- | --- |
| `install.conf.yaml` (dotbot links) | `home/default.nix` |
| `packages/Brewfile` | `home/packages.nix` |
| `packages/apt-packages` (ffmpeg, vainfo, i965 driver) | `hosts/homelab/default.nix` |
| `setup_ubuntu.zsh`: Tailscale, forwarding, UDP GRO | `modules/networking.nix` |
| `setup_ubuntu.zsh`: lid switch | `hosts/homelab/default.nix` |
| `setup_ubuntu.zsh`: Samba | `modules/storage.nix` |
| `setup_bbr.sh` | `modules/networking.nix` |
| `setup_tailscale_serve.zsh` | `modules/networking.nix` (`tailscale-serve` unit) |
| `setup_hdd_docker_mount.zsh` | `modules/storage.nix` + `modules/containers.nix` |
| `setup_docker.zsh`: daemon.json, folders | `modules/containers.nix`, `modules/storage.nix` |
| `/docker/.env` | `secrets/secrets.yaml` (sops) |
| `/docker/*-docker-compose.yml` | `modules/containers.nix` (4 examples so far) |
| `setup_rclone.zsh` | not moved. `rclone.conf` stays a real file, because rclone rewrites it. |
| `update_os.sh` | not needed on NixOS. Use `nix flake update` + `nixos-rebuild switch`. |

---

# Path A: home-manager on an existing distro

Use this path to replace brew and dotbot on Ubuntu (or another distro) without a reinstall. Each step can be undone.

## A1. Work on a branch

```bash
git switch -c nix
git add nix
```

A flake only sees files that git tracks. Staging with `git add` is enough, and you do not need to commit. Never `git add` a plain-text secrets file.

## A2. Install Nix next to brew

Brew cannot install a multi-user Nix, so Nix comes from its own installer. Use the Determinate Systems installer, because it records its changes and has a clean uninstall:

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
```

Nix does not touch `/home/linuxbrew`, apt, or Docker. Open a new shell after the install.

## A3. Fix the shell PATH for z4h

`zsh/zshenv` sets `no_global_rcs`, so zsh never reads `/etc/zshrc`, and the Nix installer adds its PATH setup there. Add this to `zsh/zshenv`, **above** the Homebrew block:

```zsh
  # Nix: no_global_rcs skips /etc/zshrc, where the installer adds this.
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  for f in ~/.nix-profile/etc/profile.d/hm-session-vars.sh \
           /etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh; do
    [[ -e $f ]] && . $f && break
  done
```

- The block goes in `zshenv`, because `ssh host cmd` and `mosh-server` do not read `.zshrc`.
- Brew stays first in PATH, because `.zshrc` runs `brew shellenv` again later. You get no change until you remove a brew package.

## A4. Install the packages only

1. In `home/default.nix`, comment out the `home.file` and `xdg.configFile` blocks.
2. Run:

   ```bash
   nix run home-manager/release-26.05 -- switch --flake ./nix#abdullah
   ```

Now each tool exists twice. Brew wins, so nothing changes yet.

## A5. Remove brew packages in small groups

```bash
~/.nix-profile/bin/yazi --version   # test the Nix copy
brew uninstall yazi                 # the Nix copy takes over
which -a yazi                       # check it
```

Some tools need extra care:

| Tool | What to do |
| --- | --- |
| `atuin` | Run `brew services stop atuin` first. Home-manager adds its own user service. |
| `gcc` | Keep apt `build-essential` on Ubuntu. It is left out of `packages.nix`. |
| `rv-r` | It is not in nixpkgs. Keep it in brew or use its own installer. |
| `claude-code` | It is in nixpkgs, but it lags and cannot update itself. Use the native installer. |
| uv tools (`ruff`, `ty`, `quarto-cli`, …) | Keep them as `uv tool install`. Nix only supplies `uv`. |
| `npm "@sanity/cli"` | Nix `node` cannot install globals into `/nix/store`. Run `npm config set prefix ~/.npm-global` first, and add `~/.npm-global/bin` to PATH. |

When brew is empty:

1. Remove the brew blocks from `zsh/zshenv` and `zsh/zshrc`.
2. Delete `/etc/sudoers.d/homebrew-path`.

## A6. Move the dotfile links from dotbot

1. Uncomment `home.file` and `xdg.configFile` in `home/default.nix`.
2. Run:

   ```bash
   home-manager switch --flake ./nix#abdullah -b hm-backup
   ```

   Home-manager stops if a dotbot link is already in place. `-b` renames the old link out of the way. It is only a link, so this loses no data.
3. From now on, **do not run `./install`**. Dotbot's `relink: true` replaces the home-manager links.

Keep `install.conf.yaml` for machines without Nix.

## A7. Check, then merge

- Open a new login shell. Check that z4h and the p10k prompt load.
- Run `ssh <host> which bat`. It must print a Nix path.
- Merge the branch.

## Undo

- **One change:** run `home-manager generations`, then run the `activate` script of an earlier generation.
- **All of Nix:** run `/nix/nix-installer uninstall`, then `git switch main`.

---

# Path B: full NixOS install

## B1. Prepare the config

Replace every `replace-me` and every machine-specific value:

| File | Value |
| --- | --- |
| `flake.nix` | `nixos-hardware.nixosModules.apple-macbook-pro-12-1`. Pick the module for the new machine, or remove the line. |
| `hosts/homelab/default.nix` | `networking.hostName`, `time.timeZone`, SSH public key |
| `hosts/homelab/default.nix` | `hardware.graphics.extraPackages`. `intel-vaapi-driver` is for Broadwell and older. Newer Intel GPUs use `intel-media-driver`. |
| `hosts/homelab/disko.nix` | `device`. Use `ls -l /dev/disk/by-id/` on the target. |
| `modules/storage.nix` | HDD UUID and `fsType`. Use `lsblk -f`. |
| `modules/networking.nix` | `lanIface` (`ip -br link`), subnet `192.168.0.0/24`, router URL for `tailscale serve` |
| `modules/containers.nix` | image tags, paths, and the full list of services |

## B2. Convert the other compose stacks

`modules/containers.nix` has four examples. Convert the rest (edge-stack, beszel, speedtest, plex, navidrome, nvr, tautulli, hysteria, mediamtx):

```bash
nix run nixpkgs#compose2nix -- \
  -inputs /docker/edge-stack-docker-compose.yml \
  -project edge-stack \
  -output nix/modules/edge-stack.nix
```

- Check that the output does not copy values from `.env` into the `.nix` file. Move each secret to sops and an `environmentFiles` entry.
- compose2nix also creates the Docker network units for multi-container stacks (such as cloudflared + caddy).
- For a simple service, a native NixOS module can replace the container. Examples: `services.jellyfin`, `services.plex`, `services.navidrome`, `services.adguardhome`, `services.caddy`, `services.cloudflared`, `services.glance`, `services.beszel`.
- The MediaMTX and Hysteria `.template` files become `sops.templates` entries. This replaces `render.sh`.

## B3. Set up secrets

1. Make your personal age key:

   ```bash
   nix shell nixpkgs#age nixpkgs#sops nixpkgs#ssh-to-age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. Get the host key.
   - **Existing host:** `ssh-keyscan <host> | ssh-to-age`
   - **New host:** make an SSH host key first (`ssh-keygen -t ed25519 -f ./ssh_host_ed25519_key -N ""`), then run `ssh-to-age < ssh_host_ed25519_key.pub`. Step B5 copies this key to the host.
3. Put both public keys in `nix/.sops.yaml`.
4. Make the encrypted file. Use the names from `secrets/secrets.example.yaml` and the values from `/docker/.env`:

   ```bash
   cd nix && sops secrets/secrets.yaml
   ```

5. Add a Tailscale auth key as `tailscale_auth_key`. Make it in the Tailscale admin console under **Settings → Keys**.

Only the encrypted `secrets/secrets.yaml` goes into git.

## B4. Back up the data

**`disko.nix` erases the target disk.** On the current box, `/docker` and `/data` are on the internal SSD. Copy them first:

```bash
sudo rsync -aHAX --info=progress2 /docker /data <backup-location>/
```

Stop the containers first (`/docker/docker-manager.sh down`), so the databases are consistent.

## B5. Install with nixos-anywhere

1. Boot the target from the NixOS minimal ISO, or use the old OS if SSH works.
2. Set a root password or add your SSH key on the target, so you can log in over SSH.
3. From another machine that has Nix, run:

   ```bash
   mkdir -p extra/etc/ssh
   cp ssh_host_ed25519_key extra/etc/ssh/        # from step B3
   chmod 600 extra/etc/ssh/ssh_host_ed25519_key

   nix run github:nix-community/nixos-anywhere -- \
     --flake ./nix#homelab \
     --generate-hardware-config nixos-generate-config ./nix/hosts/homelab/hardware-configuration.nix \
     --extra-files ./extra \
     root@<target-ip>
   ```

4. Delete the local `extra/` folder. Do not commit it.

## B6. First boot

1. Restore `/docker` and `/data` from the backup. Keep the owners as uid and gid 1000.
2. Run `sudo smbpasswd -a abdullah`.
3. Check the services:

   ```bash
   systemctl --failed
   systemctl status tailscaled-autoconnect docker-adguardhome docker-jellyfin
   tailscale status
   ```

4. Approve the exit node and subnet route in the Tailscale admin console.
5. z4h installs itself on the first zsh login.

## B7. Day-to-day use

| Task | Command |
| --- | --- |
| Apply a config change | `sudo nixos-rebuild switch --flake ./nix#homelab` |
| Update all packages | `nix flake update --flake ./nix`, then rebuild |
| Roll back | `sudo nixos-rebuild switch --rollback`, or pick an older entry in the boot menu |
| Edit secrets | `sops nix/secrets/secrets.yaml`, then rebuild |
| Update container images | `docker pull <image>`, then `systemctl restart docker-<name>` |
| Build on a faster machine | `nixos-rebuild switch --flake ./nix#homelab --target-host abdullah@<host> --use-remote-sudo` |

---

# Test before use

Nobody has evaluated this config yet. Run a check on any machine with Nix or Docker:

```bash
# With Nix
nix flake check ./nix

# Without Nix, in a throwaway container
docker run --rm -v "$PWD":/src -w /src nixos/nix \
  sh -c 'git config --global --add safe.directory /src && nix --extra-experimental-features "nix-command flakes" flake check ./nix'
```

`flake check` fails until `secrets/secrets.yaml` exists, and until the placeholder hardware file has a root filesystem. For a first test, only build the home config:

```bash
nix build ./nix#homeConfigurations.abdullah.activationPackage
```

# References

- NixOS manual: https://nixos.org/manual/nixos/stable/
- Option search: https://search.nixos.org/options
- Package search: https://search.nixos.org/packages
- home-manager: https://nix-community.github.io/home-manager/
- sops-nix: https://github.com/Mic92/sops-nix
- disko: https://github.com/nix-community/disko
- nixos-anywhere: https://github.com/nix-community/nixos-anywhere
- compose2nix: https://github.com/aksiksi/compose2nix
- nixos-hardware: https://github.com/NixOS/nixos-hardware
