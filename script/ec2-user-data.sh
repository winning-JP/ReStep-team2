#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive

# ====== Required values ======
TAILSCALE_AUTHKEY="REPLACE_WITH_TAILSCALE_AUTHKEY"
# Optional
TAILSCALE_SSH="true"
# ================================================

apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl restart docker

DEFAULT_USER=""
if id -u ubuntu >/dev/null 2>&1; then
    DEFAULT_USER="ubuntu"
    elif id -u ec2-user >/dev/null 2>&1; then
    DEFAULT_USER="ec2-user"
fi

if [ -n "${DEFAULT_USER}" ]; then
    usermod -aG docker "${DEFAULT_USER}" || true
fi

curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable tailscaled
systemctl restart tailscaled

if [ "${TAILSCALE_AUTHKEY}" != "REPLACE_WITH_TAILSCALE_AUTHKEY" ] && [ -n "${TAILSCALE_AUTHKEY}" ]; then
    if [ "${TAILSCALE_SSH}" = "true" ]; then
        tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh
    else
        tailscale up --authkey="${TAILSCALE_AUTHKEY}"
    fi
else
    echo "TAILSCALE_AUTHKEY is not set. Skipping tailscale up."
fi

echo "EC2 user-data setup completed successfully."
