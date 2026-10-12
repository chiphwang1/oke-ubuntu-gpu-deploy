#!/usr/bin/env bash
# Oracle's GPU bootstrap installs nvidia-container-toolkit. Make its signed
# production repository available before invoking oke bootstrap.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 install -y --no-install-recommends ca-certificates curl gnupg
nvidia_repo_tmp=$(mktemp -d)
trap 'rm -rf "$nvidia_repo_tmp"' EXIT
curl --fail --show-error --silent --location --retry 3 \
  https://nvidia.github.io/libnvidia-container/gpgkey \
  --output "$nvidia_repo_tmp/key.asc"
gpg --batch --yes --dearmor --output "$nvidia_repo_tmp/key.gpg" "$nvidia_repo_tmp/key.asc"
install -m 0644 "$nvidia_repo_tmp/key.gpg" /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl --fail --show-error --silent --location --retry 3 \
  https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  --output "$nvidia_repo_tmp/repository.list"
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  "$nvidia_repo_tmp/repository.list" > /etc/apt/sources.list.d/nvidia-container-toolkit.list
chmod 0644 /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get -o Acquire::Retries=3 -o APT::Update::Error-Mode=any update
nvidia_toolkit_candidate=$(apt-cache policy nvidia-container-toolkit | awk '/Candidate:/ && !seen {print $2; seen=1}')
if [[ -z "$nvidia_toolkit_candidate" || "$nvidia_toolkit_candidate" == "(none)" ]]; then
  echo 'NVIDIA repository configured, but no nvidia-container-toolkit candidate is available.' >&2
  exit 1
fi
printf 'NVIDIA Container Toolkit candidate available: %s\n' "$nvidia_toolkit_candidate"
