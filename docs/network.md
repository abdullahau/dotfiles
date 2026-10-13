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
ethtool enp0s31f6            # wired: Speed, Duplex, Auto-negotiation, Link detected
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
cat /sys/class/net/enp0s31f6/speed      # just the speed: 1000 = gigabit
ethtool enp0s31f6                       # Speed: 1000Mb/s, Duplex: Full is what you want
ethtool -S enp0s31f6 | grep -i err      # error counters (rising = bad cable/port)
```
`ethtool` works without sudo; it just prints one `netlink error: Operation not permitted` line first.
"Link partner advertised link modes" shows what the switch/router port can do; if both sides list `1000baseT/Full`, gigabit is possible.
Stuck at 100Mb/s on a gigabit port usually means a broken pair in the cable or a Cat5 cable with only two pairs. Check whether the `ethtool -S` error counters are rising.

Is the cable plugged in and is it being used?
```fish
ip -br link                  # enp0s31f6 UP,LOWER_UP = linked; NO-CARRIER = no cable / dead link
nmcli device status          # enp0s31f6 "connected" = active; "unavailable" = no cable
ip route get 1.1.1.1         # which interface internet traffic is using right now
ip monitor link              # live: a line each time a link goes up/down (also: nmcli monitor)
journalctl -u NetworkManager --since today | grep enp0s31f6   # when it connected/disconnected
```
Polybar shows the Ethernet icon and IP when it's linked, and a grey icon when it isn't (`[module/eth]`).
Wi-Fi and Ethernet can both be connected at once. Traffic uses the default route with the lowest metric:
NetworkManager gives Ethernet ~100 and Wi-Fi ~600, so a plugged-in cable wins and Wi-Fi stays up as a fallback (check with `ip route`).
That's only the **default route (internet)**. Traffic to the LAN itself follows the `192.168.0.0/24` subnet route, which can still be on Wi-Fi:
```fish
ip route get 192.168.0.1     # want: dev enp0s31f6. If it says wlan0, LAN tests (ping, iperf3) are measuring Wi-Fi
ip route | grep 192.168.0.0  # there should be a /24 route for enp0s31f6 (metric 100)
```
If the enp0s31f6 /24 route is missing, reconnect the cable: `nmcli connection up "Wired connection 1"`.
(Seen once after `conflict detected for IP address ... with host <wlan0's MAC>` in the NetworkManager log: a false conflict caused by the laptop's own Wi-Fi.)
For Ethernet only: `nmcli radio wifi off` (`on` to undo).

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
ping -c 20 192.168.0.1       # latency to the router: ~1–5 ms on Wi-Fi, under 1 ms wired
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
   Wired: is `ethtool enp0s31f6` showing 1000Mb/s, and is LAN traffic really on the cable (`ip route get 192.168.0.1` → `enp0s31f6`)?
2. `ping 192.168.0.1`: can I reach the router? Look at latency and loss.
3. `iperf3 -c homelab -R`: is LAN throughput close to what the link should give?
4. `speedtest`: does the internet match the plan?
5. `mtr 1.1.1.1`: if not, where does it degrade?
6. `resolvectl status` / `dig example.com`: if pages won't load but ping by IP works, it's DNS (AdGuard via Tailscale; see `harden.sh`).
