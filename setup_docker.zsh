#!/usr/bin/env zsh

echo "\n<<< Starting Docker Services Setup >>>\n"

echo "\n1) Installing Docker...\n"

# https://docs.docker.com/engine/install/ubuntu/
# 1) Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
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
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-model-plugin

echo "\n1a) Granting root-level Docker privilege to a non-root user"

# https://docs.docker.com/engine/install/linux-postinstall
sudo groupadd -f docker
sudo usermod -aG docker $USER
# NOTE: do NOT run `newgrp docker` here — it replaces the current shell and would
# abort the rest of this script. The new group membership takes effect on your
# next login (or run `newgrp docker` manually in a separate shell if needed now).

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


echo "\n<<< Docker Services Setup Complete >>>\n"
