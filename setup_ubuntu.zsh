#!/usr/bin/env zsh
#
# setup_ubuntu.zsh — apt packages, Tailscale (exit node + subnet router), Rust,
# logind lid-switch behaviour, and Samba.
#
# Inputs:
#   packages/apt-packages   one package per line, `#` comments allowed
#   .env at the repo root   TAILSCALE_AUTH_KEY (optional; skips `tailscale up`)
#
# Idempotent and safe to re-run.

setopt nounset  # Treat unset variables as an error

# Absolute path to this repo, whatever the cwd.
DOTFILES_DIR="${0:A:h}"

# Load local secrets from the untracked .env file.
if [[ -f "$DOTFILES_DIR/.env" ]]; then
    set -a
    source "$DOTFILES_DIR/.env"
    set +a
fi

echo "\n<<< Starting Ubuntu Setup >>>\n"

#----------------------------------------------------------------------
# Package Installation
#----------------------------------------------------------------------

echo "\n1) Installing Packages...\n"

APT_PACKAGE_LIST="$DOTFILES_DIR/packages/apt-packages"

# Homebrew on Linux needs these build dependencies first.
BREW_DEPS=(build-essential procps curl file git)

sudo apt-get update
sudo apt-get install -y "${BREW_DEPS[@]}"

# Install the listed apt packages, skipping blank lines and comments.
if [[ -f "$APT_PACKAGE_LIST" ]]; then
    apt_packages=()
    while IFS= read -r line; do
        line="${line%%#*}"            # strip inline/whole-line comments
        line="${line//[[:space:]]/}"  # strip surrounding whitespace
        [[ -n "$line" ]] && apt_packages+=("$line")
    done < "$APT_PACKAGE_LIST"

    if (( ${#apt_packages[@]} > 0 )); then
        echo "Installing apt packages: ${apt_packages[*]}"
        sudo apt-get install -y "${apt_packages[@]}"
    else
        echo "No apt packages listed in $APT_PACKAGE_LIST."
    fi
else
    echo "WARNING: $APT_PACKAGE_LIST not found; skipping apt package list."
fi

#----------------------------------------------------------------------
# Add Homebrew Bin to secure_path
#----------------------------------------------------------------------

echo "\n2) Add brew bin to secure_path...\n"

echo 'Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/linuxbrew/.linuxbrew/bin"' | sudo tee /etc/sudoers.d/homebrew-path >/dev/null
sudo visudo -c

# zsh4humans bootstraps itself from ~/.zshenv on your first zsh login.

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n3) Setting up Tailscale...\n"

curl -fsSL https://tailscale.com/install.sh | sh
if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --advertise-exit-node
else
    echo "WARNING: TAILSCALE_AUTH_KEY not set (missing .env?); skipping automatic 'tailscale up'."
    echo "         Run manually: sudo tailscale up --advertise-exit-node"
fi

echo "\n3.a) Part 1: Setting up IP Forwarding...\n"

# Write the file fresh, not append, so a re-run stays idempotent.
sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

echo "\n3.a) Part 2: Setting Up Subnet Router...\n"

sudo tailscale set --advertise-routes=192.168.0.0/24

echo "\n3.b) Linux optimizations for subnet routers and exit nodes...\n"
printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off \n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale
sudo chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

sudo /etc/networkd-dispatcher/routable.d/50-tailscale
test $? -eq 0 || echo 'An error occurred.'

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

# Use a drop-in file instead of appending to logind.conf.
LOGIND_DROPIN="/etc/systemd/logind.conf.d/99-lid-switch.conf"

echo "Writing lid switch settings to $LOGIND_DROPIN..."

sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee "$LOGIND_DROPIN" > /dev/null << 'EOF'
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF

echo "Reloading systemd-logind service to apply changes..."
sudo systemctl reload systemd-logind.service || echo "WARNING: Failed to reload systemd-logind."

#----------------------------------------------------------------------
# Samba Setup
#----------------------------------------------------------------------

echo "\n6) Setting Up Samba SMB...\n"

# https://chriskalos.notion.site/The-0-Home-Server-Written-Guide-5d5ff30f9bdd4dfbb9ce68f0d914f1f6#ad77305c83424605b859168b243ff81d
sudo ln -sf "$DOTFILES_DIR/samba/smb.conf" /etc/samba/smb.conf

sudo smbpasswd -a "$USER"
sudo systemctl restart smbd

echo "\n<<< Ubuntu Setup Complete >>>\n"
