#!/usr/bin/env zsh

setopt nounset  # Treat unset variables as an error

echo "\n<<< Starting Ubuntu Setup >>>\n"

#----------------------------------------------------------------------
# Package Installation
#----------------------------------------------------------------------

echo "\n1) Installing Packages...\n"


#----------------------------------------------------------------------
# zsh4humans Setup
#----------------------------------------------------------------------

echo "\n2) Setting up Zsh4humans...\n"

# Z4H_DIR="$HOME/.cache/zsh4humans"

# if [ -d "$Z4H_DIR" ]; then
#     echo "zsh4humans is already installed (directory found at $Z4H_DIR). Skipping installation."
# else
#     echo "zsh4humans not found. Starting installation."
#     if command -v curl >/dev/null 2>&1; then
#         sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
#     elif command -v wget >/dev/null 2>&1; then
#         sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
#     else
#         echo "Error: Neither 'curl' nor 'wget' is available for zsh4humans installation."
#     fi
# fi

# if [ -d "$Z4H_DIR" ]; then
#     echo "You may need to run 'z4h update' manually after logging into zsh for the first time."
# fi

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n3) Setting up Tailscale...\n"

curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --auth-key=tskey-auth-kJsAAcgVds11CNTRL-hii1FD7PXcLkuKhxSgfadLgr6Debkxd1 --advertise-exit-node

#----------------------------------------------------------------------
# Rust Setup
#----------------------------------------------------------------------

echo "\n4) Installing Rust toolchain via rustup...\n"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup update

#----------------------------------------------------------------------
# Logind Configuration - Lid Switch
#----------------------------------------------------------------------

echo "\n5) Configuring Logind for Lid Switch behavior...\n"

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

#----------------------------------------------------------------------
# Samba Setup
#----------------------------------------------------------------------

echo "\n5) Setting Up Samba SMB...\n"

# https://chriskalos.notion.site/The-0-Home-Server-Written-Guide-5d5ff30f9bdd4dfbb9ce68f0d914f1f6#ad77305c83424605b859168b243ff81d
sudo ln -s ~/Developer/dotfiles/samba/smb.conf /etc/samba/smb.conf

sudo smbpasswd -a abdullah
sudo systemctl restart smbd

echo "\n<<< Ubuntu Setup Complete >>>\n"
