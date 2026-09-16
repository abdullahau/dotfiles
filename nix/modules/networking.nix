{ config, lib, pkgs, ... }:
let
  lanIface = "enxc8a362d8c536";
  tailscale = "${config.services.tailscale.package}/bin/tailscale";
in
{
  # The router reserves 192.168.0.100 for this MAC.
  networking.useDHCP = lib.mkDefault true;

  # From setup_bbr.sh.
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 131072 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_mtu_probing" = 1;
  };

  sops.secrets.tailscale_auth_key = { };

  services.tailscale = {
    enable = true;
    # "server" turns on IP forwarding for the exit node and the subnet route.
    useRoutingFeatures = "server";
    authKeyFile = config.sops.secrets.tailscale_auth_key.path;
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.0.0/24"
    ];
    openFirewall = true;
  };

  # From setup_ubuntu.zsh: faster UDP forwarding for the exit node.
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = ''
        ${lib.getExe pkgs.ethtool} -K ${lanIface} rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  # From setup_tailscale_serve.zsh.
  systemd.services.tailscale-serve = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${tailscale} serve --bg --https 8443 http://192.168.0.1:80
    '';
  };

  # NixOS turns the firewall on by default. Ubuntu did not.
  # Docker-published ports skip these rules. Only host-network services need entries.
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    # AdGuard on the host network: DNS and web UI.
    allowedTCPPorts = [ 53 80 ];
    allowedUDPPorts = [ 53 ];
  };

  # The fallback resolves names before the AdGuard container starts.
  networking.nameservers = [
    "127.0.0.1"
    "1.1.1.1"
  ];
}
