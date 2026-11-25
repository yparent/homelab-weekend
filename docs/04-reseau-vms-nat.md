# Samedi 4/9 : le réseau des VMs (vmbr1 + NAT)

## Le problème

Tu as **une seule IPv4 publique**. Chez Hetzner, cette IP est liée à l'adresse MAC du serveur. Une VM branchée directement sur la carte physique sortirait avec sa propre MAC : Hetzner bloque le trafic, et peut même verrouiller le serveur pour suspicion d'abus.

## La solution

Un pont privé `vmbr1` en `10.10.10.0/24`, sans port physique. L'hôte est la passerelle (`10.10.10.1`) et fait du NAT (masquerade) : les VMs sortent sur Internet avec l'IP et la MAC de l'hôte. Même logique chez Kimsufi (une IP, MAC liée).

```text
Internet ── carte physique (IP publique) ── hôte Proxmox ── NAT ── vmbr1 10.10.10.1
                                              │                       ├── lab-vm1 10.10.10.11
                                          tailscale0                  ├── lab-vm2 10.10.10.12
                                     (subnet router 10.10.10.0/24)    └── lab-vm3 10.10.10.13
```

Depuis ton laptop, tu atteins `10.10.10.x` à travers Tailscale : l'hôte annonce ce sous-réseau (*subnet router*).

## 4.1 Créer vmbr1

**Hetzner** : le bloc `vmbr1` est déjà dans [interfaces.hetzner.example](../host/network/interfaces.hetzner.example). Ajoute-le à `/etc/network/interfaces` si tu ne l'as pas fait à l'étape 2.

**OVH** : ajoute à la fin de `/etc/network/interfaces` le bloc de [interfaces.ovh.example](../host/network/interfaces.ovh.example), sans toucher à `vmbr0`.

```bash
ifreload -a
```

**Vérifier** : `ip -br addr show vmbr1` affiche `10.10.10.1/24`.

## 4.2 Routage et NAT

Le NAT est déjà dans `/etc/homelab/homelab.nft` (étape 3) : `ip saddr 10.10.10.0/24 oifname $WAN masquerade`. Il manque le routage IPv4 :

```bash
cp /root/host/network/99-homelab-forward.conf /etc/sysctl.d/
sysctl --system
sysctl net.ipv4.ip_forward     # = 1
```

**Vérifier** : `nft list chain inet homelab postrouting` affiche la règle `masquerade`.

## 4.3 Annoncer 10.10.10.0/24 dans Tailscale

```bash
bash /root/host/tailscale-setup.sh --routes
# équivalent : tailscale set --advertise-routes=10.10.10.0/24
```

**Approuve la route** : console Tailscale > *Machines* > ton serveur (badge *Subnets*) > section *Subnets* > coche `10.10.10.0/24` > *Save*. Tant que ce n'est pas fait, la route est annoncée mais **personne ne l'utilise**.

Sur ton laptop Linux :

```bash
sudo tailscale set --accept-routes
```

(macOS, Windows, iOS et Android acceptent les routes automatiquement.)

**Vérifier** (depuis ton laptop) :

```bash
ping -c 2 10.10.10.1     # l'hôte, via la route Tailscale
```

Les VMs n'existent pas encore : tu testeras `10.10.10.11` après l'étape 7.

**Pièges**

- `ping 10.10.10.1` échoue : la route n'est pas approuvée, ou `--accept-routes` manque sur ton laptop Linux.
- Ton réseau local (box, entreprise) utilise déjà `10.10.10.0/24` : conflit de routes. Change le sous-réseau partout (`vmbr1`, `homelab.nft`, `vm_network_cidr` dans OpenTofu, la route Tailscale, les cibles Prometheus).
- Tu veux éviter l'approbation manuelle à chaque reconstruction : ajoute un `autoApprovers` dans la politique d'accès Tailscale pour `10.10.10.0/24`.

Suite : [étape 5 : le template Debian 13](05-template-debian.md).
