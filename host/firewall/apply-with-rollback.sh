#!/usr/bin/env bash
# Loads the firewall rules with an automatic rollback.
# If you lock yourself out, the table is deleted after DELAY seconds
# and you get your access back without the rescue system.
#
# Usage (as root on the Proxmox host):
#   bash apply-with-rollback.sh [rules_file] [delay_seconds]
# Then, from ANOTHER terminal, test access through Tailscale.
# If everything works: systemctl stop homelab-fw-rollback.timer
set -euo pipefail

RULES="${1:-/etc/homelab/homelab.nft}"
DELAY="${2:-300}"
UNIT="homelab-fw-rollback"

[[ ${EUID} -eq 0 ]] || { echo "lance ce script en root" >&2; exit 1; }
[[ -f "${RULES}" ]] || { echo "fichier introuvable : ${RULES}" >&2; exit 1; }

echo "Verification de la syntaxe..."
nft -c -f "${RULES}"

# Clean up a previous rollback timer, if any.
systemctl stop "${UNIT}.timer" "${UNIT}.service" 2>/dev/null || true
systemctl reset-failed "${UNIT}.timer" "${UNIT}.service" 2>/dev/null || true

# AccuracySec=1s: by default systemd may fire a timer up to 1 minute late.
systemd-run --unit="${UNIT}" --on-active="${DELAY}" --timer-property=AccuracySec=1s \
  /usr/sbin/nft delete table inet homelab

nft -f "${RULES}"

cat <<EOF

Regles chargees. Retour arriere automatique dans ${DELAY} s.

Depuis un AUTRE terminal, verifie maintenant :
  ssh root@<nom-tailscale-du-serveur>        # doit marcher
  ssh root@<IP-publique>                     # doit echouer (timeout)

Si tout va bien, annule le retour arriere :
  systemctl stop ${UNIT}.timer
EOF
