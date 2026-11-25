#!/usr/bin/env bash
# Checks that this machine can run KVM virtual machines.
# Run it on the server (rescue system or installed OS) BEFORE installing Proxmox.
# Usage: bash 00-check-virtualization.sh
set -euo pipefail

ok()   { printf '  [OK]    %s\n' "$*"; }
warn() { printf '  [WARN]  %s\n' "$*"; }
fail() { printf '  [FAIL]  %s\n' "$*"; FAILED=1; }
FAILED=0

echo "== CPU =="
cpu_model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')
echo "  Modele : ${cpu_model}"
if grep -qiE 'athlon' <<<"${cpu_model}"; then
  warn "CPU Athlon : beaucoup de ces machines n'exposent pas la virtualisation. Evite."
fi

virt_flags=$(grep -Eo '\b(vmx|svm)\b' /proc/cpuinfo | sort -u | tr '\n' ' ' || true)
if [[ -n "${virt_flags}" ]]; then
  ok "Flags de virtualisation presents : ${virt_flags}"
else
  fail "Aucun flag vmx (Intel) ou svm (AMD) : pas de KVM possible sur cette machine."
fi

echo "== Sommes-nous deja dans une VM ? =="
if command -v systemd-detect-virt >/dev/null 2>&1; then
  virt=$(systemd-detect-virt || true)
  if [[ "${virt}" == "none" ]]; then
    ok "Machine physique (systemd-detect-virt=none)"
  else
    fail "Machine virtuelle detectee (${virt}) : c'est un VPS, pas un dedie. Proxmox s'installera mais ne demarrera pas de VM."
  fi
else
  warn "systemd-detect-virt absent, verification sautee"
fi

echo "== /dev/kvm =="
if [[ -e /dev/kvm ]]; then
  ok "/dev/kvm existe"
elif command -v modprobe >/dev/null 2>&1 && { modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null; } && [[ -e /dev/kvm ]]; then
  ok "/dev/kvm existe apres chargement du module"
else
  warn "/dev/kvm absent (normal en rescue sur certains hebergeurs). Les flags CPU ci-dessus font foi."
fi
if command -v kvm-ok >/dev/null 2>&1; then
  kvm-ok || true
fi

echo "== Memoire =="
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if (( mem_gb >= 30 )); then
  ok "RAM : ${mem_gb} Go"
else
  fail "RAM : ${mem_gb} Go. Il en faut 32 pour 3 VM dont une k3s a 8 Go."
fi

echo "== Disques =="
lsblk -d -o NAME,SIZE,ROTA,TRAN,MODEL | sed 's/^/  /'
if lsblk -d -o NAME | grep -q '^nvme'; then
  ok "NVMe detecte"
else
  warn "Pas de NVMe. Ca marche, mais les clones et k3s seront plus lents (ROTA=1 = disque a plateaux)."
fi

echo
if (( FAILED )); then
  echo "RESULTAT : machine NON adaptee. Annule-la avant qu'elle te coute plus."
  exit 1
fi
echo "RESULTAT : machine adaptee pour le homelab."
