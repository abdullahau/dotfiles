{ user, ... }:
let
  share = path: {
    inherit path;
    writeable = "yes";
    public = "no";
    "follow symlinks" = "yes";
    "wide links" = "yes";
  };
in
{
  fileSystems."/mnt/hdd" = {
    device = "/dev/disk/by-uuid/replace-me"; # `lsblk -f` shows the UUID
    fsType = "ext4";
    # nofail: the box still boots when the USB disk is missing.
    options = [
      "nofail"
      "x-systemd.device-timeout=30"
    ];
  };

  systemd.tmpfiles.rules = map (d: "d ${d} 0755 ${user} ${user} -") [
    "/docker"
    "/data"
    "/data/books"
    "/data/documents"
    "/data/movies"
    "/data/music"
    "/data/shows"
    "/data/videos"
    "/data/downloads"
    "/data/downloads/complete"
    "/data/downloads/incomplete"
    "/data/downloads/torrents"
  ];

  # Samba passwords are not declarative. Run `sudo smbpasswd -a <user>` once.
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "server role" = "standalone server";
        "map to guest" = "bad user";
      };
      Data = share "/data";
      HDD = share "/mnt/hdd";
      Developer = share "/home/${user}/Developer";
    };
  };
}
