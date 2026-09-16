{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Shell and terminal
    atuin
    bat
    bat-extras.core
    btop
    eza
    fastfetch
    fd
    fzf
    micro
    ripgrep
    tlrc
    tmux
    tree
    yazi
    zellij
    zoxide

    # Git
    gh
    git
    git-filter-repo
    gitleaks
    lazydocker
    lazygit

    # Network
    iperf3
    librespeed-cli
    mosh
    rclone
    rsync

    # Files and media
    _7zz # brew "sevenzip"
    caligula
    exiftool
    imagemagick
    jq
    mkvtoolnix-cli
    pandoc
    poppler-utils
    resvg
    sqlite
    sqlite-analyzer
    tesseract

    # Languages. uv tools and npm globals stay outside Nix.
    go
    nodejs
    R
    uv
    zig
    zls

    # AI tools
    opencode
    # claude-code  # nixpkgs lags, and it cannot self-update from the store.

    # Not in nixpkgs: rv-r. Keep it in brew or use its own installer.
    # gcc: keep apt build-essential on Ubuntu. Use dev shells on NixOS.
  ];
}
