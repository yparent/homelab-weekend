#!/usr/bin/env bash
# Creates a dedicated Proxmox user + API token for OpenTofu (bpg/proxmox provider).
# Least privilege for what this repo does: clone a template, set CPU/RAM/disk/
# network/cloud-init, start/stop/destroy the VMs, read the guest agent.
# No Sys.Modify, no Permissions.Modify, no User.Modify: the token cannot
# change the host network, users or ACLs.
#
# Usage (as root on the Proxmox host):
#   bash create-tofu-user.sh
# The token secret is printed ONCE. Put it straight into your sops-encrypted
# secrets file (see docs/09-git-state-secrets.md), never in Git in clear text.
set -euo pipefail

PVE_USER="${PVE_USER:-tofu@pve}"
ROLE="${ROLE:-HomelabTofu}"
TOKEN_ID="${TOKEN_ID:-homelab}"

# Privilege names valid for Proxmox VE 9.x (VM.Monitor no longer exists,
# the guest agent is read with VM.GuestAgent.Audit).
PRIVS=(
  Datastore.AllocateSpace   # create the disks of the clones
  Datastore.Audit           # read storages
  SDN.Audit                 # see the bridges (the provider lists them)
  SDN.Use                   # plug a NIC on vmbr1
  Sys.Audit                 # read node status
  VM.Allocate               # create / destroy VMs
  VM.Audit                  # read VM config
  VM.Clone                  # clone the template
  VM.Config.CDROM           # cloud-init drive
  VM.Config.Cloudinit       # cloud-init parameters (user, SSH key, IP)
  VM.Config.CPU
  VM.Config.Disk            # resize the disk
  VM.Config.HWType          # serial console, SCSI controller
  VM.Config.Memory
  VM.Config.Network
  VM.Config.Options         # name, description, tags, on_boot
  VM.GuestAgent.Audit       # read the IPs reported by qemu-guest-agent
  VM.PowerMgmt              # start / stop
)

[[ ${EUID} -eq 0 ]] || { echo "lance ce script en root" >&2; exit 1; }

privs_csv=$(IFS=,; echo "${PRIVS[*]}")

if pveum role list --output-format json | grep -q "\"roleid\":\"${ROLE}\""; then
  pveum role modify "${ROLE}" --privs "${privs_csv}"
  echo "Role ${ROLE} mis a jour"
else
  pveum role add "${ROLE}" --privs "${privs_csv}"
  echo "Role ${ROLE} cree"
fi

if pveum user list --output-format json | grep -q "\"userid\":\"${PVE_USER}\""; then
  echo "Utilisateur ${PVE_USER} deja present"
else
  # No password: this account only exists to carry the API token.
  pveum user add "${PVE_USER}" --comment "OpenTofu homelab-weekend"
  echo "Utilisateur ${PVE_USER} cree"
fi

pveum acl modify / --users "${PVE_USER}" --roles "${ROLE}"

if pveum user token list "${PVE_USER}" --output-format json | grep -q "\"tokenid\":\"${TOKEN_ID}\""; then
  echo "Le token ${PVE_USER}!${TOKEN_ID} existe deja. Pour en refaire un :"
  echo "  pveum user token remove ${PVE_USER} ${TOKEN_ID} && bash $0"
  exit 0
fi

# privsep=0: the token has exactly the rights of the user (and the user only has this role).
echo
echo "Token (le secret n'est affiche qu'UNE fois) :"
pveum user token add "${PVE_USER}" "${TOKEN_ID}" --privsep 0 --comment "OpenTofu homelab-weekend"

cat <<EOF

Valeur a mettre dans PROXMOX_VE_API_TOKEN (fichier secrets chiffre) :
  ${PVE_USER}!${TOKEN_ID}=<value affichee ci-dessus>

Verification des droits :
  pveum user permissions ${PVE_USER} --path /
EOF
