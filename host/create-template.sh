#!/usr/bin/env bash
# Builds the Debian 13 cloud-init template used by OpenTofu.
#
# - "generic" image, NOT "genericcloud": the cloud kernel lacks the driver of
#   the IDE CD-ROM where Proxmox plugs the cloud-init drive, so cloud-init
#   often never runs on Proxmox with genericcloud.
# - qemu-guest-agent is baked into the image (virt-customize), so Proxmox and
#   OpenTofu can talk to the VM from the first boot.
#
# Usage (as root on the Proxmox host):
#   bash create-template.sh
# Override defaults with environment variables, e.g.:
#   VMID=9000 STORAGE=local-zfs BRIDGE=vmbr1 bash create-template.sh
set -euo pipefail

VMID="${VMID:-9000}"
STORAGE="${STORAGE:-local}"
BRIDGE="${BRIDGE:-vmbr1}"
TEMPLATE_NAME="${TEMPLATE_NAME:-debian-13-cloudinit}"
IMG_BASE="${IMG_BASE:-https://cloud.debian.org/images/cloud/trixie/latest}"
IMG_NAME="debian-13-generic-amd64.qcow2"
WORKDIR="${WORKDIR:-/var/lib/vz/homelab-images}"

die() { echo "ERREUR : $*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "lance ce script en root sur l'hote Proxmox"
command -v qm >/dev/null || die "qm introuvable : ce n'est pas un hote Proxmox"

if qm status "${VMID}" >/dev/null 2>&1; then
  die "la VM ${VMID} existe deja. Supprime-la (qm destroy ${VMID}) ou choisis un autre VMID."
fi

if ! pvesm status --content images 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${STORAGE}"; then
  die "le stockage '${STORAGE}' n'accepte pas les disques de VM (contenu 'images').
Stockages disponibles pour des disques :
$(pvesm status --content images 2>/dev/null | awk 'NR>1 {print "  " $1}')
Sur une install Debian+Proxmox (Hetzner), active-le sur 'local', par exemple :
  pvesm set local --content iso,vztmpl,backup,snippets,images
(garde les types deja presents dans /etc/pve/storage.cfg)"
fi

if ! command -v virt-customize >/dev/null 2>&1; then
  echo "Installation de libguestfs-tools (virt-customize)..."
  DEBIAN_FRONTEND=noninteractive apt-get -y install libguestfs-tools
fi

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "Telechargement de ${IMG_NAME} et verification SHA512..."
curl -fsSLO "${IMG_BASE}/${IMG_NAME}"
curl -fsSL -o SHA512SUMS "${IMG_BASE}/SHA512SUMS"
grep " ${IMG_NAME}\$" SHA512SUMS | sha512sum -c -

cp -f "${IMG_NAME}" "${TEMPLATE_NAME}.qcow2"

echo "Ajout de qemu-guest-agent dans l'image..."
virt-customize -a "${TEMPLATE_NAME}.qcow2" \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

echo "Creation de la VM ${VMID}..."
qm create "${VMID}" \
  --name "${TEMPLATE_NAME}" \
  --ostype l26 \
  --cpu host \
  --cores 2 \
  --memory 2048 \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-single \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0

qm set "${VMID}" --scsi0 "${STORAGE}:0,import-from=${WORKDIR}/${TEMPLATE_NAME}.qcow2,discard=on,ssd=1,iothread=1"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --boot order=scsi0
qm set "${VMID}" --tags "template;debian13"

qm template "${VMID}"

echo
echo "Template ${VMID} (${TEMPLATE_NAME}) pret sur ${STORAGE}."
qm config "${VMID}"
