#!/usr/bin/env zsh

echo "\n<<< Starting Docker Services Setup >>>\n"

echo "1) Creating Docker Container and Volume Directories...\n"

sudo mkdir -p /docker
sudo mkdir -p /data/{books,downloads,movies,music,shows}
sudo mkdir -p downloads/{complete,incomplete,torrents}

echo "\n2) Git Clone Homelab Repo...\n"

TARGET_DIR="/docker"
REPO_URL="https://github.com/abdullahau/homelab.git"

if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "No Git repository found in $TARGET_DIR. Cloning $REPO_URL..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Git repository already exists in $TARGET_DIR. Skipping clone."
    git -C "$TARGET_DIR" pull
fi

echo "\n3) Starting Docker Containers with Docker Compose...\n"

docker compose -f /docker/adguard-docker-compose.yml up -d
docker compose -f /docker/media-docker-compose.yml up -d

echo "\n4) Setting up Port 53 Bind for AdGuard Home...\n"

RESOLVED_DIR="/etc/systemd/resolved.conf.d"
sudo mkdir -p $RESOLVED_DIR
sudo tee "$RESOLVED_DIR/adguardhome.conf" > /dev/null << EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF

sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

systemctl stop systemd-resolved.service
systemctl disable systemd-resolved.service  
systemctl reload-or-restart systemd-resolved

echo "\n<<< Docker Services Setup Complete >>>\n"