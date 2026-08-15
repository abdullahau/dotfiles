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

# --accept-dns=false: a VPS must NOT adopt the tailnet's global nameserver.
# The tailnet overrides DNS to AdGuard Home on the HOME server, so without this
# every lookup on this box round-trips to the house: measured 25ms/query from
# Dubai and 259ms/query from Phoenix, versus 0-1ms via the cloud resolver.
# It also breaks things in non-obvious ways -- ad domains resolve to 0.0.0.0
# (surfacing as bogus "connection refused") and CDNs geo-resolve to the HOME
# country while this VPS egresses somewhere else entirely.
# The box keeps FULL tailnet membership; it just stops using tailnet DNS.
# Trade-off: MagicDNS names stop resolving here -- use 100.x addresses.
#
# No --advertise-exit-node either: a VPS relay only needs plain membership.
# Advertising an exit node it doesn't need makes it a route it must service.
if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    sudo tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --accept-dns=false
else
    echo "WARNING: TAILSCALE_AUTH_KEY not set (missing .env?); skipping automatic 'tailscale up'."
    echo "         Run manually: sudo tailscale up --accept-dns=false"
fi

echo "\n3.a) Part 1: Setting up IP Forwarding...\n"

# Write the file fresh (not append) so re-running setup stays idempotent.
sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# NOTE: deliberately NO subnet router here.
# The home-branch version advertises `--advertise-routes=192.168.0.0/24`, which
# is the HOME LAN and belongs only on the machine actually sitting on that LAN.
# A VPS advertising it is actively harmful: with --accept-routes on, the home
# server then routes its OWN LAN into tailscale0 and blackholes it. That is
# exactly what took the NVR camera (192.168.0.101) offline once already, via a
# stale 192.168.0.0/24 advertisement left on the Phoenix VPS.
# Verify a VPS advertises nothing with:  tailscale status --json | grep -i AdvertiseRoutes

echo "\n3.a) Part 2: Linux optimizations for tailnet forwarding...\n"
printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off \n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale
sudo chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

sudo /etc/networkd-dispatcher/routable.d/50-tailscale
test $? -eq 0 || echo 'An error occurred.'
