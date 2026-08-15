#!/usr/bin/env zsh

setopt nounset  # Treat unset variables as an error

# Absolute path to this repo, regardless of where it was cloned or the cwd.
DOTFILES_DIR="${0:A:h}"

# Load local secrets (e.g. TAILSCALE_AUTH_KEY) from an untracked .env file.
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

# Homebrew on Linux needs these build dependencies present before it can install.
BREW_DEPS=(build-essential procps curl file git)

sudo apt-get update
sudo apt-get install -y "${BREW_DEPS[@]}"

# Install packages listed in packages/apt-packages (skip blank lines and comments)
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

# Note: zsh4humans bootstraps itself from ~/.zshenv on your first interactive
# zsh login (after `chsh`), so there is no install step needed here.

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n3) Setting up Tailscale...\n"

curl -fsSL https://tailscale.com/install.sh | sh

if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --accept-dns=false --advertise-exit-node
else
    echo "WARNING: TAILSCALE_AUTH_KEY not set (missing .env?); skipping automatic 'tailscale up'."
    echo "         Run manually: sudo tailscale up --accept-dns=false --advertise-exit-node"
fi

echo "\n3.a) Part 1: Setting up IP Forwarding...\n"

# Write the file fresh (not append) so re-running setup stays idempotent.
sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

echo "\n3.a) Part 2: Linux optimizations for tailnet forwarding...\n"
printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off \n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale
sudo chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

sudo /etc/networkd-dispatcher/routable.d/50-tailscale
test $? -eq 0 || echo 'An error occurred.'
