#!/usr/bin/env python3
"""Find live hosts on one or more networks, with hostnames and open ports.

Usage examples:
  python3 netscan.py                          # scan every subnet routed through your VPN/LAN
  python3 netscan.py 130.0.0.0/24 192.168.2.0/24
  python3 netscan.py 172.16.20.0/24 --dns 130.0.0.1 --ports 22,80,443,8080
  python3 netscan.py --list-subnets           # just show which subnets your Mac can reach

A host counts as "live" if it answers ping OR has one of the scanned TCP ports open
(so hosts that block ping are still found). Only uses the Python standard library.
Results are printed as a table and saved to netscan-<date>.csv.
"""
import argparse
import concurrent.futures as cf
import csv
import datetime
import ipaddress
import re
import socket
import subprocess
import sys

DEFAULT_PORTS = [22, 80, 443, 3389, 8080]


def routed_subnets():
    """Subnets routed through VPN tunnels (utun*/ppp*) or the local LAN, from `netstat -rn`."""
    out = subprocess.run(["netstat", "-rn", "-f", "inet"], capture_output=True, text=True).stdout
    nets = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4 or not re.match(r"^(utun|ppp|en|ipsec)\d+", parts[3]):
            continue
        dest = parts[0]
        if dest in ("default",) or dest.startswith(("127", "169.254", "224.", "255.")):
            continue
        # netstat abbreviates: "130.0" means 130.0.0.0/16, "172.16.20/24" means 172.16.20.0/24
        addr, _, plen = dest.partition("/")
        if not plen and "link#" not in parts[1]:
            continue  # single-host route
        octets = addr.split(".")
        dest = ".".join(octets + ["0"] * (4 - len(octets))) + "/" + (plen or str(8 * len(octets)))
        try:
            net = ipaddress.ip_network(dest, strict=False)
        except ValueError:
            continue
        if net.prefixlen < 32 and not net.subnet_of(ipaddress.ip_network("100.64.0.0/10")):
            nets.add((net, parts[3]))
    return sorted(nets)


def ping(ip):
    r = subprocess.run(["ping", "-c", "1", "-t", "1", str(ip)], capture_output=True)
    return r.returncode == 0


def open_ports(ip, ports, timeout):
    found = []
    for p in ports:
        try:
            with socket.create_connection((str(ip), p), timeout=timeout):
                found.append(p)
        except OSError:
            pass
    return found


def ssh_banner(ip, timeout):
    try:
        with socket.create_connection((str(ip), 22), timeout=timeout) as s:
            s.settimeout(timeout)
            return s.recv(100).decode(errors="replace").splitlines()[0].strip()
    except OSError:
        return ""


def reverse_dns(ip, dns_server):
    if dns_server:
        r = subprocess.run(["dig", "+short", "+time=1", "+tries=2", "-x", str(ip), f"@{dns_server}"],
                           capture_output=True, text=True).stdout.strip().splitlines()
        names = [n.rstrip(".") for n in r if n and not n.startswith(";")]
        return names[0] if names else ""
    try:
        return socket.gethostbyaddr(str(ip))[0]
    except OSError:
        return ""


def netbios_name(ip):
    r = subprocess.run(["smbutil", "status", "-t", "2", str(ip)], capture_output=True, text=True).stdout
    m = re.search(r"Server:\s*(\S+)", r)
    return m.group(1) if m else ""


def check(ip, ports, timeout, dns_server):
    alive = ping(ip)
    opened = open_ports(ip, ports, timeout)
    if not alive and not opened:
        return None
    name = reverse_dns(ip, dns_server)
    if not name:
        nb = netbios_name(ip)
        name = f"{nb} (NetBIOS)" if nb else ""
    banner = ssh_banner(ip, timeout) if 22 in opened else ""
    return {"ip": str(ip), "hostname": name, "ping": "yes" if alive else "no",
            "open_ports": " ".join(map(str, opened)), "ssh_banner": banner}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("networks", nargs="*", help="CIDR ranges, e.g. 192.168.1.0/24 (default: all routed subnets)")
    ap.add_argument("--ports", default=",".join(map(str, DEFAULT_PORTS)), help="comma-separated TCP ports")
    ap.add_argument("--dns", help="DNS server for hostname lookups (e.g. your office domain controller)")
    ap.add_argument("--timeout", type=float, default=1.0)
    ap.add_argument("--workers", type=int, default=64, help="parallel probes (keep under ~150 on macOS)")
    ap.add_argument("--max-hosts", type=int, default=4096, help="refuse to scan more addresses than this")
    ap.add_argument("--list-subnets", action="store_true")
    a = ap.parse_args()

    if a.list_subnets or not a.networks:
        subnets = routed_subnets()
        print("Reachable subnets (interface):")
        for net, iface in subnets:
            print(f"  {net}  via {iface}  ({net.num_addresses - 2} addresses)")
        if a.list_subnets:
            return
        nets = [n for n, _ in subnets]
    else:
        nets = [ipaddress.ip_network(n, strict=False) for n in a.networks]

    hosts = [h for n in nets for h in n.hosts()]
    if len(hosts) > a.max_hosts:
        sys.exit(f"{len(hosts)} addresses is too many; pass smaller ranges (e.g. a /24) or raise --max-hosts")
    ports = [int(p) for p in a.ports.split(",") if p]
    print(f"Scanning {len(hosts)} addresses on ports {ports} ...", file=sys.stderr)

    with cf.ThreadPoolExecutor(a.workers) as ex:
        rows = [r for r in ex.map(lambda h: check(h, ports, a.timeout, a.dns), hosts) if r]
    rows.sort(key=lambda r: ipaddress.ip_address(r["ip"]))

    for r in rows:
        print(f"{r['ip']:<16} {r['hostname'][:40]:<40} ping={r['ping']:<3} ports=[{r['open_ports']}] {r['ssh_banner']}")
    out = f"netscan-{datetime.datetime.now():%Y%m%d-%H%M}.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys() if rows else ["ip"])
        w.writeheader()
        w.writerows(rows)
    print(f"\n{len(rows)} live hosts. Saved to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
