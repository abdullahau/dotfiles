# dotfiles (`vps` branch)

Bootstrap and configuration for a public-facing VPS (currently `oracle-dxb`,
an Oracle Cloud free-tier instance). The VPS has no services of its own — its
job is to sit on a public IP and give the homelab server, which has neither a
fixed IP nor router port forwarding, a public front door over Tailscale.

## Bootstrap a fresh VPS

```bash
sudo apt-get update && sudo apt-get install -y git
ssh-keygen -t ed25519 -C "abdullah.au@outlook.com"
cat ~/.ssh/id_ed25519.pub   # add to GitHub → Settings → SSH keys
ssh -T git@github.com

git clone git@github.com:abdullahau/dotfiles.git ~/Developer/dotfiles
cd ~/Developer/dotfiles
git checkout vps

cp .env.example .env               # TAILSCALE_AUTH_KEY
cp vps/.env.example vps/.env       # TARGET_IP, RELAY_PORTS, LOCAL_PORTS
$EDITOR .env vps/.env

./install
```

`./install` runs Dotbot, which symlinks configs into place, then runs the
setup scripts in this order: `setup_ubuntu.zsh` (apt packages, Tailscale),
`setup_homebrew.zsh` (Brewfile), `setup_docker.zsh` (Docker Engine), then
three VPS-specific scripts described below. Safe to re-run.

## The relay: two hops, not one

A client never reaches the homelab directly. Every request crosses two hops:

1. **Public hop** — the client connects to the VPS's public IP.
2. **Tailscale hop** — the VPS forwards that request to the homelab's
   Tailscale IP, over the encrypted tailnet. The homelab never accepts a
   direct inbound connection from the internet; it only replies to a tunnel
   it joined itself. This is why no router port forwarding is needed at home.

The public hop can be built two ways — **raw relay** or **reverse proxy** —
and picking the right one per service matters.

## Raw relay (DNAT) vs. Caddy (reverse proxy)

| | Raw relay (`vps/relay.sh`) | Caddy reverse proxy (`vps/caddy/Caddyfile`) |
|---|---|---|
| Routes by | destination **port** | **hostname** (Host header / TLS SNI) |
| Many services, one port (443) | No — one port = one backend | Yes, this is the point |
| HTTPS | Only if the app manages its own cert | Automatic, free, per subdomain |
| Protocol | Any TCP/UDP | HTTP(S) and WebSocket only |
| New service costs | a new port + a new OCI ingress rule | one Caddyfile block, same 80/443 |
| Overhead | Kernel-level NAT, minimal | Small (TLS termination), negligible for streaming |

Rule of thumb: **raw relay for anything that isn't plain HTTP, or that
manages its own TLS/remote-access system** (Plex, SSH). **Reverse proxy for
normal web apps** — no new port, no new OCI rule, a clean subdomain.

Video is not a reason to prefer raw relay. Jellyfin and Navidrome deliver
video/audio over plain HTTP range requests — exactly what a reverse proxy is
built for. Caddy doesn't transcode or buffer the stream; it only terminates
TLS and relays bytes, which a modern CPU does at multi-gigabit speed.

## Current services

| Service | Where it runs | Method | Public address |
|---|---|---|---|
| Plex | homelab `:32400` | raw relay (`RELAY_PORTS`) | `abdullah.run:32400`, plus `plex.abdullah.run` / `plex.abdullah.diy` via Caddy |
| Navidrome | homelab `:4533` | Caddy reverse proxy | `navidrome.abdullah.run` / `.diy` |
| marimo / Jupyter | VPS itself `:8080` | local port (`LOCAL_PORTS`) | `abdullah.run:8080` |
| Jellyfin | homelab `:8096` (not yet running) | Caddy reverse proxy, once confirmed live | `jellyfin.abdullah.run` / `.diy` |

Plex keeps its raw relay even though it also has a Caddy alias — Plex's own
apps expect port 32400 directly and use their own `plex.direct` certificate.
The subdomain is a convenience extra, not a replacement. Adding it required
two settings on the Plex server (Settings → Network):
- **Custom server access URLs**: `https://plex.abdullah.run:443,https://plex.abdullah.diy:443`
- **Secure connections**: `Preferred` (not `Required` — Required locks Plex to
  its own cert on 32400 and rejects Caddy's).

## The `vps/` folder

Three self-contained scripts, each safe to copy alone to any VPS:

- **`vps/relay.sh`** — DNATs a public port to a service on another tailnet
  host. Reads `TARGET_IP` / `RELAY_PORTS` from `vps/.env`.
- **`vps/local-ports.sh`** — opens a public port for a service running on the
  VPS itself (no relay). Reads `LOCAL_PORTS` from `vps/.env`.
- **`vps/caddy/Caddyfile`** — the reverse-proxy config (see next section).
- **`vps/caddy/docker-compose.yml`** — reference copy only. The live one runs
  from `~/Developer/home/deploy/`, where its relative paths resolve.

`setup_bbr.sh` (TCP congestion tuning) stays at the repo root, not inside
`vps/` — it isn't relay-specific. It speeds up any TCP connection through the
box, DNAT-relayed or Caddy-proxied alike, and is meant to run identically on
both the VPS and the homelab server.

Both `relay.sh` and `local-ports.sh` are idempotent (re-run any time after
editing `vps/.env`) and self-persist across reboots via a systemd oneshot
unit, independent of `iptables-persistent`.

## Caddy: two copies, kept in sync by hand

The live Caddy container runs from `~/Developer/home/deploy/`, which also
mounts that repo's `public/` and `media/` (the site content). `vps/caddy/Caddyfile`
here is a duplicate, kept as the VPS-setup reference copy. **Edit both when
you change routing** — there is no symlink or shared mount between them
today (a deliberate choice, to keep the two repos independent).

To apply a change to the live site:
```bash
docker exec deploy-caddy-1 caddy reload --config /etc/caddy/Caddyfile
```

## Cloudflare DNS gotchas

Both `abdullah.run` and `abdullah.diy` are on Cloudflare, free plan,
**proxied** (orange cloud) for the main site.

- **Proxied hostnames only forward a fixed list of ports** — not arbitrary
  ones. HTTP: 80, 8080, 8880, 2052, 2082, 2086, 2095. HTTPS: 443, 2053, 2083,
  2087, 2096, 8443. This is why `abdullah.run:8080` (marimo) works but
  `abdullah.run:32400` (Plex) does not — 32400 isn't on the list, so
  Cloudflare drops it at the edge before it ever reaches the VPS.
- Any subdomain that needs a **non-whitelisted port reachable directly**
  (Plex on 32400) must be **DNS only** (grey cloud) in Cloudflare, so it
  resolves straight to the VPS's public IP.
- Media-streaming subdomains behind Caddy (Navidrome, Jellyfin) work fine
  proxied (443 is whitelisted), but grey-cloud is still preferred for them:
  Cloudflare's free/Pro terms discourage using the proxy as a primary video
  channel, and a direct connection avoids an extra buffering layer.

## Adding a new service — checklist

**Reverse proxy (default choice):**
1. Confirm the service is reachable from the VPS over Tailscale:
   `curl http://<homelab-tailscale-ip>:<port>`.
2. Add a block to `vps/caddy/Caddyfile` **and** `~/Developer/home/deploy/Caddyfile`.
3. Add a DNS record in Cloudflare for the subdomain, pointed at the VPS's
   public IP (grey cloud for media services).
4. `docker exec deploy-caddy-1 caddy reload --config /etc/caddy/Caddyfile`.

**Raw relay (only for non-HTTP or self-certifying apps):**
1. Add the port to `RELAY_PORTS` in `vps/.env`.
2. Re-run `./vps/relay.sh`.
3. Open the port in the OCI console: Compute → Instance → attached VNIC →
   Subnet → Default Security List → Ingress Rules.

## Packages

- [`packages/Brewfile`](packages/Brewfile) — Homebrew formulae/casks + `uv`
  and `npm` packages.
- [`packages/apt-packages`](packages/apt-packages) — apt packages, one per
  line.
