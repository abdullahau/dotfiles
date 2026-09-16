# dotfiles — `vps` branch

Config for a public VPS (`oracle-dxb`, Oracle Cloud free tier). The VPS runs
no services of its own. It gives the homelab server, which has no fixed IP or
router port forwarding, a public front door through Tailscale.

Branches: `main` (macOS), `homelab` (home server), `vps` (this server).

## Bootstrap

```bash
sudo apt-get update && sudo apt-get install -y git
ssh-keygen -t ed25519 -C "abdullah.au@outlook.com"    # add the .pub key to GitHub
git clone git@github.com:abdullahau/dotfiles.git ~/Developer/dotfiles
cd ~/Developer/dotfiles && git checkout vps
cp .env.example .env && cp vps/.env.example vps/.env
$EDITOR .env vps/.env    # TAILSCALE_AUTH_KEY, TARGET_IP, RELAY_PORTS, LOCAL_PORTS
./install
```

`./install` is safe to run again.

## What `./install` runs

| Script | Does |
| --- | --- |
| `setup_ubuntu.zsh` | apt packages, joins the tailnet |
| `setup_homebrew.zsh` | Homebrew and everything in `packages/Brewfile` |
| `setup_docker.zsh` | installs Docker Engine, enables IPv6 |
| `vps/relay.sh` | forwards public ports to a service on another tailnet host (reads `vps/.env`) |
| `vps/local-ports.sh` | opens public ports for a service running on this VPS itself |
| `setup_bbr.sh` | turns on TCP BBR and fq pacing |

## Run by hand

```bash
./vps/relay.sh          # re-run after editing RELAY_PORTS in vps/.env
./vps/local-ports.sh    # re-run after editing LOCAL_PORTS in vps/.env
./setup_bbr.sh
```

## The relay: two hops

A client never reaches the homelab directly. Each request crosses two hops:

1. **Public hop** — the client connects to the VPS's public IP.
2. **Tailscale hop** — the VPS forwards the request to the homelab over the
   tailnet. The homelab never accepts a direct inbound connection; it only
   replies to a tunnel it joined itself.

There are two ways to expose a service on the public hop:

| | Raw relay (`vps/relay.sh`) | Caddy reverse proxy (`vps/caddy/`) |
| --- | --- | --- |
| Routes by | port | hostname |
| HTTPS | only if the app manages its own cert | automatic, per subdomain |
| Use for | non-HTTP apps, or apps with their own TLS (Plex, SSH) | normal web apps |

## Current services

| Service | Runs on | Method | Public address |
| --- | --- | --- | --- |
| Plex | homelab `:32400` | raw relay + Caddy alias | `abdullah.run:32400`, `plex.abdullah.run` / `.diy` |
| Navidrome | homelab `:4533` | Caddy | `navidrome.abdullah.run` / `.diy` |
| marimo / Jupyter | VPS `:8080` | local port | `abdullah.run:8080` |
| Tailscale peer relay | VPS `:40000/udp` | local port | tailnet devices only |
| Jellyfin | homelab `:8096` | Caddy (once live) | `jellyfin.abdullah.run` / `.diy` |

## Tailscale peer relay

This VPS is a Tailscale peer relay on UDP `40000`. This is separate from
`vps/relay.sh`. It carries tailnet traffic between two devices that cannot
connect directly, for example the homelab (reachable over IPv6) and a phone on
an IPv4-only network. Without it, that traffic goes through Tailscale's DERP
servers, which are slower.

Setup:

1. Add `40000/udp` to `LOCAL_PORTS` in `vps/.env`, then run `./vps/local-ports.sh`.
2. In OCI, add an ingress rule: source `0.0.0.0/0`, protocol UDP, port `40000`.
3. Run `sudo tailscale set --relay-server-port=40000`.
4. In the tailnet policy, tag the VPS `tag:relay` and add this grant:

   ```json
   {
       "src": ["autogroup:member", "tag:server"],
       "dst": ["tag:relay"],
       "app": {"tailscale.com/cap/relay": []},
   },
   ```

   Keep the allow-all grant next to it. If you remove it, the tailnet blocks
   all other traffic.

Check it with `sudo tailscale debug peer-relay-sessions`.

## Caddy

The live Caddy container runs from `~/Developer/home/deploy/`. The file
`vps/caddy/Caddyfile` here is a reference copy — edit both when routing
changes, then reload the live one:

```bash
docker exec deploy-caddy-1 caddy reload --config /etc/caddy/Caddyfile
```

## Packages

- `packages/Brewfile` — Homebrew formulae, casks, and `uv` tools.
- `packages/apt-packages` — apt packages, one per line. `#` starts a comment.

## Oracle Cloud

`oracle-cloud/` holds the OCI CLI setup and scripts for this tenancy. See
`oracle-cloud/README.md`.
