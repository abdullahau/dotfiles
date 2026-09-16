# Examples for four stacks. Generate the rest with compose2nix, e.g.:
#   compose2nix -inputs /docker/edge-stack-docker-compose.yml -project edge-stack
# Check that the output does not copy values from .env into the .nix file.
{ config, lib, ... }:
let
  tz = "Asia/Dubai";
  ids = {
    PUID = "1000";
    PGID = "1000";
    TZ = tz;
  };
  secret = name: config.sops.placeholder.${name};
  envFile = name: config.sops.templates.${name}.path;
in
{
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      ipv6 = true;
      fixed-cidr-v6 = "fd00::/80";
      experimental = true;
      ip6tables = true;
    };
    autoPrune.enable = true;
  };

  virtualisation.oci-containers.backend = "docker";

  sops.secrets = {
    host_ts_ip = { };
    adguard_username = { };
    adguard_password = { };
    speedtest_api_token = { };
    transmission_username = { };
    transmission_password = { };
  };

  # sops-nix renders these at boot. Only root can read them. Nothing lands in /nix/store.
  sops.templates."glance.env".content = ''
    HOST_TS_IP=${secret "host_ts_ip"}
    ADGUARD_USERNAME=${secret "adguard_username"}
    ADGUARD_PASSWORD=${secret "adguard_password"}
    SPEEDTEST_API_TOKEN=${secret "speedtest_api_token"}
  '';

  sops.templates."transmission.env".content = ''
    USER=${secret "transmission_username"}
    PASS=${secret "transmission_password"}
  '';

  # Pin image tags before you rely on this. ":latest" is not reproducible.
  virtualisation.oci-containers.containers = {
    adguardhome = {
      image = "adguard/adguardhome:latest";
      # Host network, so AdGuard sees real client IPs.
      extraOptions = [ "--network=host" ];
      environment.TZ = tz;
      volumes = [
        "/docker/adguard-home/work:/opt/adguardhome/work"
        "/docker/adguard-home/confdir:/opt/adguardhome/conf"
      ];
    };

    glance = {
      image = "glanceapp/glance:latest";
      environment = ids;
      environmentFiles = [ (envFile "glance.env") ];
      ports = [ "8080:8080" ];
      volumes = [
        "/docker/glance/config:/app/config"
        "/docker/glance/assets:/app/assets"
        "/etc/localtime:/etc/localtime:ro"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
    };

    transmission = {
      image = "lscr.io/linuxserver/transmission:latest";
      environment = ids // {
        PEERPORT = "51413";
      };
      environmentFiles = [ (envFile "transmission.env") ];
      ports = [
        "9091:9091"
        "51413:51413"
        "51413:51413/udp"
      ];
      volumes = [
        "/docker/transmission:/config"
        "/data:/downloads"
        "/data/downloads/torrents:/watch"
        "/mnt/hdd:/hdd"
      ];
    };

    jellyfin = {
      image = "jellyfin/jellyfin:latest";
      user = "1000:1000";
      ports = [
        "8096:8096/tcp"
        "7359:7359/udp"
      ];
      volumes = [
        "/docker/jellyfin/config:/config"
        "/docker/jellyfin/cache:/cache"
        "/data/movies:/movies"
        "/data/shows:/shows"
        "/mnt/hdd:/hdd"
      ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
      # Uncomment for hardware transcoding.
      # devices = [ "/dev/dri:/dev/dri" ];
    };
  };

  # Start these only after the USB disk mounts. This replaces setup_hdd_docker_mount.zsh.
  systemd.services =
    lib.genAttrs
      [
        "docker-transmission"
        "docker-jellyfin"
      ]
      (_: {
        unitConfig.RequiresMountsFor = [ "/mnt/hdd" ];
      });
}
