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
# SSH Setup
#----------------------------------------------------------------------

echo "\n4) Setting up OpenSSH...\n"

sudo systemctl start sshd || echo "WARNING: SSH service failed to enable/start."
sudo systemctl enable sshd || echo "WARNING: SSH service failed to enable/start."

SSH_STATUS=$(sudo systemctl status sshd 2>/dev/null)
if [ -n "$SSH_STATUS" ]; then
    echo "SSH is active"
else
    echo "WARNING: SSH is not active"
fi

sudo ufw allow 22/tcp

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n5) Setting up Tailscale...\n"

sudo systemctl enable --now tailscaled || echo "WARNING: Tailscale service failed to enable/start."
sudo tailscale up

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
if [ -n "$TAILSCALE_IP" ]; then
    echo "Tailscale IPv4 Address: $TAILSCALE_IP"
else
    echo "WARNING: Could not retrieve Tailscale IPv4 address."
fi

echo "\n5.a) Setting Up Exit Node...\n"

sudo tailscale set --advertise-exit-node

echo "\n5.b) Setting Up Subnet Router...\n"

sudo tailscale set --advertise-routes=192.168.0.0/24

echo "\n5.b) Part 2: Setting up IP Forwarding...\n"

echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

#----------------------------------------------------------------------
# Plex Setup
#----------------------------------------------------------------------

echo "\n6) Setting up Plex Media Server...\n"

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

echo "\n7) Setting up Monitor Configuration...\n"

MONITOR_CONFIG="$HOME/.config/hypr/monitors.conf"
MONITOR_DOTFILE="./hypr/monitors.conf"

cat $MONITOR_DOTFILE > $MONITOR_CONFIG

echo "\nMonitor configuration written to $MONITOR_CONFIG.\n"

#----------------------------------------------------------------------
# Logind Configuration - Lid Switch
#----------------------------------------------------------------------

echo "\n8) Configuring Logind for Lid Switch behavior...\n"

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