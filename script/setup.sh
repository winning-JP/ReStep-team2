#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
	echo "このスクリプトは root で実行してください。" >&2
	exit 1
fi

: "${TAILSCALE_AUTHKEY:?TAILSCALE_AUTHKEY を環境変数で指定してください}"

apt-get update -y
apt-get upgrade -y

apt-get install -y ca-certificates curl gnupg

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
systemctl start docker

usermod -aG docker ubuntu

curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable tailscaled
systemctl start tailscaled

tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh