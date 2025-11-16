#!/usr/bin/env zsh

echo "\n<<< Starting Docker Services Setup >>>\n"

echo "\n1) Installing Docker...\n"

# https://docs.docker.com/engine/install/ubuntu/
# 1) Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 2) Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# 3) Install Docker packages
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "\n1a) Granting root-level Docker privilege to a non-root user"

# https://docs.docker.com/engine/install/linux-postinstall
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker

echo "\n2) Enable IPv6 in Docker Daemon...\n"

sudo tee /etc/docker/daemon.json > /dev/null << EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80",
  "experimental": true,
  "ip6tables": true
}
EOF

echo "\n3) Enable IPv6 on Host System...\n"

cat << EOF | sudo tee -a /etc/sysctl.conf > /dev/null

net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF

echo "\n2) Creating Docker Container Directory and Volume Directories...\n"

sudo mkdir -p /docker
sudo mkdir -p /data/{books,documents,downloads,movies,music,shows,videos}
sudo mkdir -p /data/downloads/{complete,incomplete,torrents}

echo "\n3) Changing Ownership and Permissions to $USER...\n"

# Change ownership
sudo chown -R "$USER":"$USER" /docker
sudo chown -R "$USER":"$USER" /data

# Change permissions
sudo chmod -R 755 /docker
sudo chmod -R 755 /data

echo "\n4) Git Clone Homelab Repo...\n"

TARGET_DIR="/docker"
REPO_URL="git@github.com:abdullahau/homelab.git"

if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "No Git repository found in $TARGET_DIR. Cloning $REPO_URL..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Git repository already exists in $TARGET_DIR. Skipping clone."
    git -C "$TARGET_DIR" pull
fi

echo "\n5) Starting Docker Containers with Docker Compose...\n"

/docker/docker-manager.sh up

echo "\n6) Setting up Port 53 Bind for AdGuard Home...\n"

RESOLVED_DIR="/etc/systemd/resolved.conf.d"
sudo mkdir -p $RESOLVED_DIR
sudo tee "$RESOLVED_DIR/adguardhome.conf" > /dev/null << EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF

sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# systemctl stop systemd-resolved.service
# systemctl disable systemd-resolved.service
systemctl reload-or-restart systemd-resolved

echo "\n<<< Docker Services Setup Complete >>>\n"
