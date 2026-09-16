{ pkgs, user, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/networking.nix
    ../../modules/storage.nix
    ../../modules/containers.nix
  ];

  networking.hostName = "homelab";
  time.timeZone = "Asia/Dubai";
  i18n.defaultLocale = "en_US.UTF-8";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        user
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Keep uid and gid 1000 so PUID/PGID and the file owners on the HDD still match.
  users.groups.${user}.gid = 1000;
  users.users.${user} = {
    isNormalUser = true;
    uid = 1000;
    group = user;
    extraGroups = [
      "wheel"
      "docker"
      "video"
      "render"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA-replace-me"
    ];
  };

  # Needed for a zsh login shell. z4h sets no_global_rcs, so /etc/zshrc stays unused.
  programs.zsh.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.mosh.enable = true;

  # The laptop runs with the lid shut.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
  };

  # uv Python builds and z4h downloads are generic Linux binaries.
  programs.nix-ld.enable = true;

  hardware.graphics = {
    enable = true;
    # Broadwell needs i965, not iHD. The hybrid codec matches apt's i965-va-driver-shaders.
    extraPackages = [ (pkgs.intel-vaapi-driver.override { enableHybridCodec = true; }) ];
  };

  environment.systemPackages = with pkgs; [
    ethtool
    ffmpeg
    git
    libva-utils
  ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    # Decrypt with the host SSH key. No extra key file to copy.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  system.stateVersion = "26.05";
}
