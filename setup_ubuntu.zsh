#!/usr/bin/env zsh
#
# setup_ubuntu.zsh — apt packages, Tailscale (exit node + subnet router), Rust,
# logind lid-switch behaviour, Samba, and disabling unused services.
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

# zsh config comes from dotbot: ~/.zshrc and ~/.zshenv link into zsh/.

#----------------------------------------------------------------------
# Tailscale Setup
#----------------------------------------------------------------------

echo "\n3) Setting up Tailscale...\n"

# A release upgrade leaves tailscale.list.disabled behind and never restores it,
# stranding Tailscale on the old release. Clear it so install.sh writes a fresh repo.
sudo rm -f /etc/apt/sources.list.d/tailscale.list \
           /etc/apt/sources.list.d/tailscale.list.disabled

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

# A systemd upgrade can replace logind.conf and take appended lines with it,
# leaving this laptop to suspend on lid close. A drop-in survives that.
LOGIND_DROPIN="/etc/systemd/logind.conf.d/99-lid-switch.conf"

echo "Writing lid switch settings to $LOGIND_DROPIN..."

sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee "$LOGIND_DROPIN" > /dev/null << 'EOF'
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF

# Keep these settings in the drop-in only, not also appended to logind.conf.
if sudo grep -q '^# ------- Custom Lid Switch Settings -------' /etc/systemd/logind.conf 2>/dev/null; then
    echo "Removing the older appended block from /etc/systemd/logind.conf..."
    sudo sed -i '/^# ------- Custom Lid Switch Settings -------$/,/^# ------------------------------------------$/d' /etc/systemd/logind.conf
fi

echo "Reloading systemd-logind service to apply changes..."
sudo systemctl reload systemd-logind.service || echo "WARNING: Failed to reload systemd-logind."

#----------------------------------------------------------------------
# GRUB - headless single-OS boot
#----------------------------------------------------------------------

echo "\n5.a) Configuring GRUB for a headless single-OS boot...\n"

# Never edit /etc/default/grub: ucf prompts on every grub upgrade. Use a drop-in
# and leave the package file alone, so upgrades stay silent.
sudo mkdir -p /etc/default/grub.d
sudo tee /etc/default/grub.d/99-homelab.cfg > /dev/null << 'EOF'
# Headless, one OS on the disk: boot straight through and skip the os-prober scan.
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_DISABLE_OS_PROBER=true
EOF

# An earlier hand-edit left ucf holding the package version. Take it back.
if [[ -f /etc/default/grub.ucf-dist ]]; then
    echo "Restoring the package /etc/default/grub; the drop-in carries our settings."
    sudo cp -a /etc/default/grub /etc/default/grub.before-reset
    sudo cp -a /etc/default/grub.ucf-dist /etc/default/grub
    sudo rm -f /etc/default/grub.ucf-dist
fi

sudo update-grub

#----------------------------------------------------------------------
# Samba Setup
#----------------------------------------------------------------------

echo "\n6) Setting Up Samba SMB...\n"

# https://chriskalos.notion.site/The-0-Home-Server-Written-Guide-5d5ff30f9bdd4dfbb9ce68f0d914f1f6#ad77305c83424605b859168b243ff81d
#
# A samba upgrade replaces the symlink with a plain copy and adds new defaults to
# it. Fold that back in before relinking, so the addition is kept not discarded.
if [[ -f /etc/samba/smb.conf && ! -L /etc/samba/smb.conf ]]; then
    if ! diff -q /etc/samba/smb.conf "$DOTFILES_DIR/samba/smb.conf" >/dev/null; then
        echo "/etc/samba/smb.conf is a plain file and differs from the repo."
        echo "Folding it back into $DOTFILES_DIR/samba/smb.conf; review with 'git diff'."
        cat /etc/samba/smb.conf > "$DOTFILES_DIR/samba/smb.conf"
    fi
fi

sudo ln -sfn "$DOTFILES_DIR/samba/smb.conf" /etc/samba/smb.conf
sudo testparm -s >/dev/null || echo "WARNING: testparm rejected smb.conf; not restarting smbd."

sudo smbpasswd -a "$USER"
sudo systemctl restart smbd

#----------------------------------------------------------------------
# Disable Unused Services
#----------------------------------------------------------------------

echo "\n7) Disabling unused services (snapd, multipathd, nmbd)...\n"

# No snaps (brew does that job), no multipath disks, and smbd serves the shares
# without NetBIOS. Mask the sockets too, or they start the services on demand.
UNUSED_UNITS=(snapd.service snapd.socket multipathd.service multipathd.socket nmbd.service)

sudo systemctl disable --now "${UNUSED_UNITS[@]}" snapd.seeded.service \
    snapd.apparmor.service snapd.autoimport.service snapd.core-fixup.service \
    snapd.recovery-chooser-trigger.service snapd.system-shutdown.service \
    snapd.snap-repair.timer 2>/dev/null
sudo systemctl mask "${UNUSED_UNITS[@]}"

echo "\n<<< Ubuntu Setup Complete >>>\n"
