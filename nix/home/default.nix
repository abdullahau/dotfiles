{ config, user, ... }:
let
  dotfiles = "${config.home.homeDirectory}/Developer/dotfiles";
  # Live links into the repo, the same as dotbot makes. Edits need no rebuild.
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  imports = [ ./packages.nix ];

  home.username = user;
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # z4h owns zsh. Do not enable programs.zsh: it would write its own .zshrc.
  home.file = {
    ".zshrc".source = link "zsh/zshrc";
    ".zshenv".source = link "zsh/zshenv";
    ".p10k.zsh".source = link "zsh/p10k.zsh";
    ".inputrc".source = link "zsh/inputrc";
    ".zfunc".source = link "zsh/zfunc";
    ".gitconfig".source = link "git/gitconfig";
    ".gitignore_global".source = link "git/gitignore_global";
    ".ssh/config".source = link "ssh/config";
    ".claude/CLAUDE.md".source = link "claude/CLAUDE.md";
  };

  xdg.configFile = {
    "micro".source = link "micro";
    "yazi".source = link "yazi";
    "bat".source = link "bat";
    "fastfetch".source = link "fastfetch";
    "btop".source = link "btop";
    "atuin".source = link "atuin";
    "zellij".source = link "zellij";
    "codebook".source = link "codebook";
    "ruff".source = link "ruff";
    # rclone.conf stays a real file: rclone rewrites it on token refresh.
    "rclone/rclone-filters.txt".source = link "rclone/rclone-filters.txt";
  };

  # Replaces the brew service. atuin also autostarts it, so this is optional.
  systemd.user.services.atuin-daemon = {
    Unit.Description = "atuin daemon";
    Service = {
      ExecStart = "${config.home.profileDirectory}/bin/atuin daemon start";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
