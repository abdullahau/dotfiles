#!/usr/bin/env zsh

setopt nounset  # Treat unset variables as an error

echo "\n<<< Starting Omarchy Setup >>>\n"

#----------------------------------------------------------------------
# Package Installation
#----------------------------------------------------------------------

echo "\n1) Installing Packages...\n"

sudo pacman -Syu --needed - < packages/Pacman || { echo "ERROR: Pacman installation failed."; exit 1; }
yay -Syu --needed - < packages/AUR || { echo "ERROR: AUR installation failed."; exit 1; }

#----------------------------------------------------------------------
# Omarchy Bloat Cleaner (https://github.com/maxart/omarchy-cleaner)
#----------------------------------------------------------------------

echo "\n2) Running Omarchy Cleaner...\n"

read -q "REPLY?Do you want to run the Omarchy Bloat Cleaner? (y/N) "

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "\nRunning Omarchy Bloat Cleaner...\n"
    curl -fsSL https://raw.githubusercontent.com/maxart/omarchy-cleaner/main/omarchy-cleaner.sh | bash || echo "WARNING: Cleaner script failed but continuing."
else
    echo "\nSkipping Omarchy Bloat Cleaner.\n"
fi

#----------------------------------------------------------------------
# zsh4humans Setup
#----------------------------------------------------------------------

echo "\n3) Setting up Zsh4humans...\n"

Z4H_DIR="$HOME/.cache/zsh4humans"

if [ -d "$Z4H_DIR" ]; then
    echo "zsh4humans is already installed (directory found at $Z4H_DIR). Skipping installation."
else
    echo "zsh4humans not found. Starting installation."
    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
    elif command -v wget >/dev/null 2>&1; then
        sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
    else
        echo "Error: Neither 'curl' nor 'wget' is available for zsh4humans installation."
    fi
fi

if [ -d "$Z4H_DIR" ]; then
    echo "You may need to run 'z4h update' manually after logging into zsh for the first time."
fi

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n4) Setting up Tailscale...\n"

sudo systemctl enable --now tailscaled || echo "WARNING: Tailscale service failed to enable/start."
sudo tailscale up

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
if [ -n "$TAILSCALE_IP" ]; then
    echo "Tailscale IPv4 Address: $TAILSCALE_IP"
else
    echo "WARNING: Could not retrieve Tailscale IPv4 address."
fi

#----------------------------------------------------------------------
# Plex Setup
#----------------------------------------------------------------------

echo "\n5) Setting up Plex Media Server...\n"

sudo systemctl enable plexmediaserver.service || echo "WARNING: Plex service enable failed."
sudo systemctl start plexmediaserver.service || echo "WARNING: Plex service start failed."


PLEX_UFW_FILE="/etc/ufw/applications.d/plexmediaserver"
PLEX_DOTFILE="./plex/plexmediaserver"

echo "Writing UFW definition to $PLEX_UFW_FILE..."

cat "$PLEX_DOTFILE" | sudo tee "$PLEX_UFW_FILE" > /dev/null || echo "ERROR: Failed to write Plex UFW file."

if command -v ufw >/dev/null 2>&1; then
    echo "Updating and allowing Plex in UFW..."
    if sudo ufw status | grep -q "active"; then
        sudo ufw app update plexmediaserver
        sudo ufw allow plexmediaserver-all
        echo "Plex UFW rule added."
    else
        echo "UFW is installed but not active. Skipping rule application."
    fi
else
    echo "UFW command not found. Skipping rule setup."
fi

#----------------------------------------------------------------------
# Monitor Configuration
#----------------------------------------------------------------------

echo "\n6) Setting up Monitor Configuration...\n"

MONITOR_CONFIG="$HOME/.config/hypr/monitors.conf"
MONITOR_DOTFILE="./hypr/monitors.conf"

cat $MONITOR_DOTFILE > $MONITOR_CONFIG

echo "\nMonitor configuration written to $MONITOR_CONFIG.\n"

#----------------------------------------------------------------------
# Logind Configuration - Lid Switch
#----------------------------------------------------------------------

echo "\n7) Configuring Logind for Lid Switch behavior...\n"

LOGIND_CONF="/etc/systemd/logind.conf"

echo "Appending lid switch settings to $LOGIND_CONF..."

cat << EOF | sudo tee -a "$LOGIND_CONF" > /dev/null


# --- Omarchy Custom Lid Switch Settings ---
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
# ------------------------------------------
EOF

echo "Reloading systemd-logind service to apply changes..."
sudo systemctl reload systemd-logind.service || echo "WARNING: Failed to reload systemd-logind."


echo "\n<<< Omarchy Setup Complete >>>\n"