#!/usr/bin/env bash
# Installs Proxmox VE 9 on top of a fresh Debian 13 (Trixie).
# Follows the official wiki procedure:
#   https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
#
# Two phases, with a reboot in between (the Proxmox kernel must be running
# before the Proxmox packages are installed):
#   sudo bash install-proxmox-on-debian13.sh phase1   # repo + Proxmox kernel, then reboot
#   sudo bash install-proxmox-on-debian13.sh phase2   # Proxmox packages, cleanup
#
# Hetzner users: keep the Robot rescue system and the remote console at hand.
set -euo pipefail

KEYRING_URL="https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
KEYRING_PATH="/usr/share/keyrings/proxmox-archive-keyring.gpg"
# Checksum published on the wiki page (checked 2026-11-25).
KEYRING_SHA256="136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45"

die() { echo "ERREUR : $*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "lance ce script en root"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == "trixie" ]] || die "Debian 13 (trixie) attendu, trouve : ${PRETTY_NAME:-inconnu}"

check_hostname() {
  local ip
  ip=$(hostname --ip-address 2>/dev/null | awk '{print $1}')
  if [[ -z "${ip}" || "${ip}" == 127.* || "${ip}" == "::1" ]]; then
    die "le nom d'hote '$(hostname)' resout vers '${ip:-rien}'. Ajoute dans /etc/hosts une ligne
  <IP_PUBLIQUE>  $(hostname -f 2>/dev/null || hostname) $(hostname -s)
et retire le nom d'hote de la ligne 127.0.1.1 (voir docs/02-installer-proxmox.md)."
  fi
  echo "OK : $(hostname) -> ${ip}"
}

phase1() {
  check_hostname

  cat > /etc/apt/sources.list.d/pve-install-repo.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

  wget -q "${KEYRING_URL}" -O "${KEYRING_PATH}"
  echo "${KEYRING_SHA256}  ${KEYRING_PATH}" | sha256sum -c - \
    || die "empreinte de la cle Proxmox inattendue. Verifie la page wiki officielle avant d'aller plus loin."

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
  DEBIAN_FRONTEND=noninteractive apt-get -y install proxmox-default-kernel

  echo
  echo "Phase 1 terminee. Redemarre maintenant : systemctl reboot"
  echo "Apres le redemarrage, 'uname -r' doit se terminer par '-pve', puis lance : $0 phase2"
}

check_network_config() {
  # Proxmox uses ifupdown2 and reads /etc/network/interfaces.
  # If the provider configured the network with systemd-networkd, the server
  # comes back WITHOUT network after the next reboot. We refuse to continue.
  if ! grep -qE '^\s*gateway\s' /etc/network/interfaces 2>/dev/null; then
    die "/etc/network/interfaces ne contient aucune passerelle.
Ton reseau est sans doute gere par systemd-networkd (cas frequent chez Hetzner).
Ecris d'abord /etc/network/interfaces a partir de host/network/interfaces.hetzner.example,
avec l'IP, le prefixe et la passerelle ACTUELS (ip -4 addr ; ip route), puis relance phase2."
  fi
  echo "OK : /etc/network/interfaces contient une passerelle"
}

disable_enterprise_repos() {
  # Without a subscription, the enterprise repos answer 401 and break 'apt update'.
  local f
  for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
    if [[ -f "${f}" ]] && grep -q 'enterprise.proxmox.com' "${f}" && ! grep -q '^Enabled: *false' "${f}"; then
      echo "Enabled: false" >> "${f}"
      echo "Depot entreprise desactive : ${f}"
    fi
  done
}

phase2() {
  [[ "$(uname -r)" == *-pve ]] || die "le noyau Proxmox ne tourne pas ($(uname -r)). As-tu redemarre apres phase1 ?"
  check_hostname
  check_network_config

  # Answer the postfix questions in advance: local delivery only.
  echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
  echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections

  DEBIAN_FRONTEND=noninteractive apt-get -y install proxmox-ve postfix open-iscsi chrony

  # Remove the Debian kernel (the wiki requires it) and os-prober.
  DEBIAN_FRONTEND=noninteractive apt-get -y remove linux-image-amd64 'linux-image-6.12*' || true
  update-grub
  DEBIAN_FRONTEND=noninteractive apt-get -y remove os-prober || true

  disable_enterprise_repos
  apt-get update

  if systemctl is-enabled --quiet systemd-networkd 2>/dev/null; then
    echo
    echo "ATTENTION : systemd-networkd est encore actif. Avant de redemarrer :"
    echo "  systemctl disable systemd-networkd.service systemd-networkd.socket"
    echo "  rm -f /etc/systemd/network/*.network   # apres avoir verifie /etc/network/interfaces"
  fi

  echo
  echo "Phase 2 terminee. pveversion :"
  pveversion
  echo "Redemarre (rescue a portee de main), puis connecte-toi a https://<IP>:8006 (root, realm PAM)."
  echo "Ferme ce port des l'etape 3 (Tailscale + pare-feu)."
}

case "${1:-}" in
  phase1) phase1 ;;
  phase2) phase2 ;;
  *) echo "Usage : $0 phase1|phase2" >&2; exit 2 ;;
esac
