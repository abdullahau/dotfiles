#!/usr/bin/env zsh
#
# setup_docker.zsh — install Docker Engine, enable IPv6, create the media and
# container directories, then clone and start the private homelab stack.
#
# Inputs:
#   A GitHub SSH key that can read git@github.com:abdullahau/homelab.git. Without
#   it the clone, the container start, and the AdGuard DNS bind are skipped.
#
# Idempotent and safe to re-run.

echo "\n<<< Starting Docker Services Setup >>>\n"

echo "\n1) Installing Docker...\n"

# https://docs.docker.com/engine/install/ubuntu/
# 1) Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 2) Add the repository to Apt sources.
# A release upgrade renames third-party .list files to .list.disabled and never
# restores them, stranding Docker on the old release. Clear those and write .sources.
UBUNTU_CODENAME_NOW="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.list.disabled

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null << EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME_NOW}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update

# 3) Install Docker packages
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-model-plugin

echo "\n1a) Granting root-level Docker privilege to a non-root user"

# https://docs.docker.com/engine/install/linux-postinstall
sudo groupadd -f docker
sudo usermod -aG docker $USER
# Do not run `newgrp docker` here: it replaces the shell and aborts this script.
# The new group takes effect on your next login.

echo "\n2) Enable IPv6 in Docker Daemon...\n"

# fixed-cidr-v6 only reaches docker0. Compose networks stay IPv4-only unless they
# set enable_ipv6, and fd00::/80 is a ULA with no route off this host.
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80",
  "experimental": true,
  "ip6tables": true
}
EOF

echo "\n3) Enable IPv6 on Host System...\n"

# Ubuntu 26.04 ships no /etc/sysctl.conf, and appending to it stacked a copy per run.
sudo tee /etc/sysctl.d/99-docker-ipv6.conf > /dev/null << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF
sudo sysctl -p /etc/sysctl.d/99-docker-ipv6.conf

echo "\n4) Creating Docker Container Directory and Volume Directories...\n"

sudo mkdir -p /docker
sudo mkdir -p /data/{books,documents,downloads,movies,music,shows,videos}
sudo mkdir -p /data/downloads/{complete,incomplete,torrents}

echo "\n5) Changing Ownership and Permissions to $USER...\n"

# Change ownership
sudo chown -R "$USER":"$USER" /docker
sudo chown -R "$USER":"$USER" /data

# Change permissions
sudo chmod -R 755 /docker
sudo chmod -R 755 /data

echo "\n6) Git Clone Homelab Repo...\n"

TARGET_DIR="/docker"
REPO_URL="git@github.com:abdullahau/homelab.git"

# The homelab repo is private, so the clone needs an SSH key on GitHub. Skip the
# dependent steps instead of failing when the key is not there yet.
homelab_ready=false

if [ -d "$TARGET_DIR/.git" ]; then
    echo "Git repository already exists in $TARGET_DIR. Pulling latest..."
    git -C "$TARGET_DIR" pull && homelab_ready=true
else
    echo "No Git repository found in $TARGET_DIR. Cloning $REPO_URL..."
    if git clone "$REPO_URL" "$TARGET_DIR"; then
        homelab_ready=true
    else
        echo "WARNING: Could not clone $REPO_URL (SSH key not set up on GitHub yet?)."
        echo "         Skipping container start + AdGuard DNS bind. Re-run this"
        echo "         script after adding your SSH key to finish homelab setup."
    fi
fi

if [ "$homelab_ready" = true ] && [ -x "$TARGET_DIR/docker-manager.sh" ]; then
    echo "\n7) Starting Docker Containers with Docker Compose...\n"
    "$TARGET_DIR/docker-manager.sh" up

    echo "\n8) Setting up Port 53 Bind for AdGuard Home...\n"

    # AdGuard needs port 53, so resolved gives up its stub listener.
    RESOLVED_DIR="/etc/systemd/resolved.conf.d"
    sudo mkdir -p $RESOLVED_DIR

    # Step 8a stops Tailscale supplying the search domain, so set it here.
    MAGIC_DNS_SUFFIX="$(tailscale status --json 2>/dev/null | jq -r '.MagicDNSSuffix // empty')"

    sudo tee "$RESOLVED_DIR/adguardhome.conf" > /dev/null << EOF
[Resolve]
DNS=127.0.0.1
FallbackDNS=1.1.1.1 9.9.9.9
DNSStubListener=no
${MAGIC_DNS_SUFFIX:+Domains=${MAGIC_DNS_SUFFIX}}
EOF

    echo "\n8a) Handing DNS to AdGuard instead of Tailscale...\n"

    # --accept-dns points resolv.conf at 100.100.100.100, which sends every lookup
    # out over tailscale0 and back to AdGuard here. Let AdGuard answer directly.
    #
    # AdGuard then needs this upstream, or MagicDNS names stop resolving:
    #     [/${MAGIC_DNS_SUFFIX:-your-tailnet.ts.net}/]100.100.100.100
    if [ -n "$MAGIC_DNS_SUFFIX" ]; then
        sudo tailscale set --accept-dns=false
    else
        echo "WARNING: could not read the MagicDNS suffix; leaving Tailscale DNS alone."
    fi

    # Back up a real file once, so a re-run does not clobber the real backup.
    if [ ! -L /etc/resolv.conf ]; then
        sudo mv /etc/resolv.conf /etc/resolv.conf.backup
    fi
    sudo ln -sfn /run/systemd/resolve/resolv.conf /etc/resolv.conf

    sudo systemctl reload-or-restart systemd-resolved
else
    echo "\nSkipping container start and AdGuard DNS bind (homelab repo not ready)."
fi

echo "\n<<< Docker Services Setup Complete >>>\n"
