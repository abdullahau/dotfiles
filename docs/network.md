# Network cheatsheet

Interfaces on this laptop: Wi-Fi `wlan0`, Ethernet `enp0s31f6`, Tailscale `tailscale0`. Home LAN: `192.168.0.0/24`.
Tools (in `packages.txt`): `iperf3 iw ethtool wavemon nmap arp-scan mtr bandwhich`, AUR `ookla-speedtest-bin`.

> **OpenSnitch** will ask about `iperf3`, `speedtest`, `nmap` and `mtr` the first time they connect out (only while its UI is open, otherwise they're blocked).
> **ufw** denies incoming, so this laptop can't be an iperf3 server on the LAN unless you open the port (see below).

## Quick look: what is my connection doing right now?
```fish
ip -br addr                  # interfaces, up/down, IPs
iw dev wlan0 link            # Wi-Fi: SSID, freq, signal dBm, tx/rx bitrate, MCS, channel width
nmcli dev wifi               # nearby networks: channel, rate, signal, security (* = connected)
sudo ethtool enp0s31f6       # wired: Speed, Duplex, Auto-negotiation, Link detected
```

## Wi-Fi signal and link
```fish
iw dev wlan0 link            # snapshot
iw dev wlan0 station dump    # detail: signal avg, tx retries/failed, connected time, expected throughput
iw dev wlan0 info            # channel, width, tx power
wavemon                      # live TUI: F1 info, F2 level histogram, F3 nearby APs (scan), q quit
nmcli dev wifi rescan; nmcli -f SSID,CHAN,FREQ,RATE,SIGNAL,BARS dev wifi
```

Signal (dBm, closer to 0 is better):

| dBm | Means |
|---|---|
| −30 to −55 | Excellent |
| −55 to −67 | Good: fine for calls and streaming |
| −67 to −75 | Fair: speed drops, occasional glitches |
| below −75 | Poor: drops, very low rates |

`tx bitrate` is the negotiated link rate (PHY). Real throughput is usually 50–70% of it.
Busy channel? Compare channels in `nmcli dev wifi` and move the router off the crowded one (2.4 GHz: only 1, 6, 11).

## Wired link
```fish
sudo ethtool enp0s31f6                  # Speed: 1000Mb/s, Duplex: Full is what you want
sudo ethtool -S enp0s31f6 | grep -i err # error counters (rising = bad cable/port)
```
100Mb/s on a gigabit port usually means a damaged cable or one with only 4 wires connected.

## LAN throughput: iperf3
Needs iperf3 at both ends: one machine is the server, the other the client.
Best: server on a **wired** machine (e.g. `homelab`), client on the device being tested.

```fish
iperf3 -s                               # on the server (port 5201)

iperf3 -c <server-ip>                   # upload (client → server), 10 s
iperf3 -c <server-ip> -R                # download (server → client)
iperf3 -c <server-ip> --bidir           # both directions at once
iperf3 -c <server-ip> -t 30 -P 4        # 30 s, 4 parallel streams (fills fast links)
iperf3 -c <server-ip> -u -b 0           # UDP flat out: jitter + packet loss
iperf3 -c <server-ip> -u -b 50M         # UDP at 50 Mbit/s (e.g. simulate a video stream)
```
- Over the tailnet use the Tailscale IP or name (`iperf3 -c homelab`). That measures through the WireGuard tunnel, so it's slower than the raw LAN.
- To make **this laptop** the server on the LAN, open the port while testing:
  ```fish
  sudo ufw allow from 192.168.0.0/24 to any port 5201 proto tcp
  sudo ufw allow from 192.168.0.0/24 to any port 5201 proto udp
  # afterwards
  sudo ufw delete allow from 192.168.0.0/24 to any port 5201 proto tcp
  sudo ufw delete allow from 192.168.0.0/24 to any port 5201 proto udp
  ```
- Phones/TVs without iperf: run OpenSpeedTest or LibreSpeed in Docker on `homelab` and open it in their browser.

## Internet speed and quality
```fish
speedtest                    # Ookla: down/up, idle + loaded latency, jitter, packet loss
speedtest -L                 # nearby servers
speedtest -s <id>            # test against a specific server
mtr 1.1.1.1                  # live per-hop latency/loss; find where it goes bad
mtr -rwc 100 1.1.1.1         # 100-cycle report (good to paste into a support ticket)
ping -c 20 192.168.0.1       # latency to the router (should be ~1–5 ms on Wi-Fi)
```
- Loss at a middle hop that doesn't carry on to the last hop is just that router slowing down its replies. Ignore it.
- Lag when someone is uploading or downloading is **bufferbloat**: compare idle vs loaded latency in `speedtest`, or use the Waveform bufferbloat test in a browser.
- Wi-Fi vs ISP problem? Run `iperf3` to `homelab` (LAN) and `speedtest` (internet). If the LAN result is good and the internet one is bad, the problem is the ISP.

## Devices on the network
```fish
sudo arp-scan -l                          # every device: IP, MAC, vendor (fast)
sudo nmap -sn 192.168.0.0/24              # ping sweep (also shows MAC/vendor with sudo)
sudo nmap 192.168.0.50                    # top 1000 open ports on one device
sudo nmap -sV -O 192.168.0.50             # + service versions and OS guess
sudo nmap -A -T4 192.168.0.50             # everything (versions, OS, scripts, traceroute)
nmap -p 22,80,443,8080 192.168.0.0/24     # who has these ports open
ip neigh                                  # devices this laptop has talked to recently
tailscale status                          # tailnet devices, direct vs relayed (DERP)
```
Phones with randomised MACs show as "unknown" vendor in `arp-scan`. That's normal.
Only scan networks you own or are allowed to scan.

## Live traffic on this laptop
```fish
sudo bandwhich               # bandwidth per process / connection / remote host
sudo bandwhich -i wlan0      # one interface
ss -tunp                     # open connections and which process owns them
```

## Troubleshooting order
1. `iw dev wlan0 link`: is the signal OK (better than −67) and is the bitrate sensible?
2. `ping 192.168.0.1`: can I reach the router? Look at latency and loss.
3. `iperf3 -c homelab -R`: is LAN throughput close to what the link should give?
4. `speedtest`: does the internet match the plan?
5. `mtr 1.1.1.1`: if not, where does it degrade?
6. `resolvectl status` / `dig example.com`: if pages won't load but ping by IP works, it's DNS (AdGuard via Tailscale; see `harden.sh`).
