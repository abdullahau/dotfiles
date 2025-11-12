#!/usr/bin/env zsh

echo "\n<<< Starting Docker Services Setup >>>\n"

echo "1) Installing Rust toolchain via rustup...\n"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup update

echo "1) Creating Docker Container Directory and Volume Directories...\n"

sudo mkdir -p /docker
sudo mkdir -p /data/{books,downloads,movies,music,shows}
sudo mkdir -p /data/downloads/{complete,incomplete,torrents}

echo "\n2) Changing Ownership and Permissions to $USER...\n"

# Change ownership
sudo chown -R "$USER":"$USER" /docker
sudo chown -R "$USER":"$USER" /data

# Change permissions 
sudo chmod -R 755 /docker
sudo chmod -R 755 /data

echo "\n3) Git Clone Homelab Repo...\n"

TARGET_DIR="/docker"
REPO_URL="https://github.com/abdullahau/homelab.git"

if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "No Git repository found in $TARGET_DIR. Cloning $REPO_URL..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Git repository already exists in $TARGET_DIR. Skipping clone."
    git -C "$TARGET_DIR" pull
fi

echo "\n4) Starting Docker Containers with Docker Compose...\n"

docker compose -f /docker/adguard-docker-compose.yml up -d
docker compose -f /docker/media-docker-compose.yml up -d

echo "\n5) Setting up Port 53 Bind for AdGuard Home...\n"

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
