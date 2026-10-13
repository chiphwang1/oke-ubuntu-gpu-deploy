#!/usr/bin/env bash
# Run only after a successful `oke bootstrap` on Ubuntu workers using CRI-O and runc.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
packages=(nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container1 libnvidia-container-tools)

wait_for_runtime() {
  local deadline=$((SECONDS + 180))
  until systemctl is-active --quiet crio.service && systemctl is-active --quiet kubelet.service; do
    if (( SECONDS >= deadline )); then
      echo 'Timed out waiting for CRI-O and kubelet after bootstrap.' >&2
      return 1
    fi
    sleep 2
  done
}
wait_for_runtime
command -v runc >/dev/null
# Do not remove executables referenced by an NVIDIA runtime or OCI hook.
for config_dir in /etc/crio /etc/containers/oci/hooks.d /usr/share/containers/oci/hooks.d; do
  if [[ -d "$config_dir" ]] && grep -RsqE 'nvidia-container-(runtime|runtime-hook)|default_runtime[[:space:]]*=[[:space:]]*"nvidia"' "$config_dir"; then
    echo "Refusing toolkit removal: NVIDIA runtime/hook reference in $config_dir" >&2
    exit 1
  fi
done

simulation=$(apt-get -s purge "${packages[@]}")
printf '%s\n' "$simulation"
while read -r package; do
  case "$package" in
    nvidia-container-toolkit|nvidia-container-toolkit-base|libnvidia-container1|libnvidia-container-tools) ;;
    *) echo "Refusing unexpected dependency removal: $package" >&2; exit 1 ;;
  esac
done < <(printf '%s\n' "$simulation" | awk '$1 == "Remv" || $1 == "Purg" {print $2}')

apt-get -o DPkg::Lock::Timeout=300 purge -y "${packages[@]}"
for package in "${packages[@]}"; do
  status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
  if [[ -n "$status" && "$status" != "not-installed" ]]; then
    echo "Toolkit package still present: $package ($status)" >&2
    exit 1
  fi
done
wait_for_runtime
install -d -m 0755 /var/lib/oke-toolkit-removal
date -u +%FT%TZ > /var/lib/oke-toolkit-removal/complete
echo 'PASS: OKE bootstrap complete; NVIDIA toolkit packages removed; CRI-O and kubelet active.'
