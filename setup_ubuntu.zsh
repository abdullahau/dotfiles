#!/usr/bin/env zsh

setopt nounset  # Treat unset variables as an error

echo "\n<<< Starting Ubuntu Setup >>>\n"

#----------------------------------------------------------------------
# Package Installation
#----------------------------------------------------------------------

echo "\n1) Installing Packages...\n"


#----------------------------------------------------------------------
# Omarchy Bloat Cleaner (https://github.com/maxart/omarchy-cleaner)
#----------------------------------------------------------------------

echo "\n2) Running Omarchy Cleaner...\n"


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


#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n5) Setting up Tailscale...\n"


#----------------------------------------------------------------------
# Plex Setup
#----------------------------------------------------------------------

echo "\n6) Setting up Plex Media Server...\n"


#----------------------------------------------------------------------
# Logind Configuration - Lid Switch
#----------------------------------------------------------------------

echo "\n8) Configuring Logind for Lid Switch behavior...\n"

LOGIND_CONF="/etc/systemd/logind.conf"

echo "Appending lid switch settings to $LOGIND_CONF..."

cat << EOF | sudo tee -a "$LOGIND_CONF" > /dev/null


# --- Custom Lid Switch Settings ---
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
# ------------------------------------------
EOF

echo "Reloading systemd-logind service to apply changes..."
sudo systemctl reload systemd-logind.service || echo "WARNING: Failed to reload systemd-logind."


echo "\n<<< Ubuntu Setup Complete >>>\n"
