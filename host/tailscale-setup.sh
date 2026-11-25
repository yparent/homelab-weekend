#!/usr/bin/env bash
# Installs Tailscale on the Proxmox host and (optionally) advertises the VM subnet.
#
# Usage (as root on the Proxmox host):
#   bash tailscale-setup.sh            # step 3: join the tailnet
#   bash tailscale-setup.sh --routes   # step 4: become the subnet router for 10.10.10.0/24
#
# The first run prints a login URL: open it in your browser to add the server.
set -euo pipefail

SUBNET="${SUBNET:-10.10.10.0/24}"

[[ ${EUID} -eq 0 ]] || { echo "lance ce script en root" >&2; exit 1; }

if ! command -v tailscale >/dev/null 2>&1; then
  # Official install script: adds the Tailscale apt repo for Debian 13 and installs the package.
  curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

if [[ "${1:-}" == "--routes" ]]; then
  install -m 0644 "$(dirname "$0")/network/99-homelab-forward.conf" /etc/sysctl.d/99-homelab-forward.conf
  sysctl --system >/dev/null
  tailscale set --advertise-routes="${SUBNET}"
  cat <<EOF
Route ${SUBNET} annoncee.
Il reste a l'APPROUVER : console admin Tailscale > Machines > ce serveur > section Subnets > coche ${SUBNET} > Save.
Sur un poste Linux, active la reception des routes : sudo tailscale set --accept-routes
(macOS, Windows, iOS, Android les acceptent automatiquement.)
EOF
else
  # Joins the tailnet. Prints an auth URL the first time.
  tailscale up
  echo
  echo "IP Tailscale de ce serveur : $(tailscale ip -4)"
  echo "Teste depuis ton poste : ssh root@$(tailscale ip -4)"
fi
