#!/usr/bin/env zsh

echo "\n<<< Starting Omarchy Setup >>>\n"

#----------------------------------------------------------------------
# Package Installation
#----------------------------------------------------------------------

echo "\nInstalling Packages...\n"

sudo pacman -S --needed - < packages/Pacman
yay -S --needed - < packages/AUR

#----------------------------------------------------------------------
# Omarchy Bloat Cleaner (https://github.com/maxart/omarchy-cleaner)
#----------------------------------------------------------------------

read -q "REPLY?Do you want to run the Omarchy Bloat Cleaner? (y/N) "

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "\nRunning Omarchy Bloat Cleaner...\n"
    curl -fsSL https://raw.githubusercontent.com/maxart/omarchy-cleaner/main/omarchy-cleaner.sh | bash
else
    echo "\nSkipping Omarchy Bloat Cleaner.\n"
fi

#----------------------------------------------------------------------
# zsh4humans Setup
#----------------------------------------------------------------------

if command -v z4h >/dev/null 2>&1; then
    echo "zsh4humans (z4h) is already installed. Skipping installation."
else
    echo "zsh4humans (z4h) not found. Starting installation."
    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
    elif command -v wget >/dev/null 2>&1; then
        sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
    else
        echo "Error: Neither 'curl' nor 'wget' is available for zsh4humans installation."
    fi
fi

# Run update only if z4h is now installed (either previously or newly installed)
if command -v z4h >/dev/null 2>&1; then
    z4h update
fi

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\nSetting up Tailscale...\n"

sudo systemctl enable --now tailscaled
sudo tailscale up
tailscale ip -4

#----------------------------------------------------------------------
# Plex Setup
#----------------------------------------------------------------------

echo "\nSetting up Plex Media Server...\n"

systemctl enable plexmediaserver.service
systemctl start plexmediaserver.service

PLEX_UFW_FILE="/etc/ufw/applications.d/plexmediaserver"
sudo tee "$PLEX_UFW_FILE" > /dev/null << EOF
[plexmediaserver]
title=Plex Media Server (Standard)
description=The Plex Media Server
ports=32400/tcp|3005/tcp|5353/udp|8324/tcp|32410:32414/udp

[plexmediaserver-dlna]
title=Plex Media Server (DLNA)
description=The Plex Media Server (additional DLNA capability only)
ports=1900/udp|32469/tcp

[plexmediaserver-all]
title=Plex Media Server (Standard + DLNA)
description=The Plex Media Server (with additional DLNA capability)
ports=32400/tcp|3005/tcp|5353/udp|8324/tcp|32410:32414/udp|1900/udp|32469/tcp
EOF


if command -v ufw >/dev/null 2>&1; then
    if sudo ufw status | grep -q "active"; then
        sudo ufw app update plexmediaserver
        sudo ufw allow plexmediaserver-all
        echo "Plex UFW rule added."
    else
        echo "UFW is not active. Skipping rule application."
    fi
else
    echo "UFW command not found. Skipping rule setup."
fi

echo "\n<<< Omarchy Setup Complete >>>\n"
