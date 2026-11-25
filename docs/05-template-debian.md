# Samedi 5/9 : le template Debian 13

Le template est l'image de base que OpenTofu clone 3 fois. Tu le crées une fois, à la main, avec un script.

## Pourquoi l'image « generic » et pas « genericcloud »

Debian publie plusieurs images cloud. `genericcloud` utilise un noyau allégé, sans les pilotes de matériel « physique ». Or Proxmox branche le disque cloud-init comme un **lecteur CD IDE**. Avec `genericcloud`, ce lecteur est souvent invisible : cloud-init ne trouve pas sa configuration, la VM démarre sans ton utilisateur, sans ta clé SSH, sans IP. L'image `generic` a le noyau complet : ça marche.

## 5.1 Préparer le stockage

Le template et les VMs ont besoin d'un stockage qui accepte les disques de VM (type de contenu `images`).

```bash
pvesm status --content images
```

- **OVH** (gabarit Proxmox 9, ZFS) : tu vois en général `local-zfs`. Utilise-le.
- **Hetzner** (Debian + Proxmox, ext4) : souvent rien. Active les disques sur `local` en **gardant** les types déjà présents (regarde `/etc/pve/storage.cfg`) :

```bash
grep -A3 '^dir: local' /etc/pve/storage.cfg
pvesm set local --content iso,vztmpl,backup,snippets,images
```

**Vérifier** : `pvesm status --content images` liste ton stockage.

## 5.2 Créer le template

```bash
STORAGE=local bash /root/host/create-template.sh      # ou STORAGE=local-zfs
```

Ce que fait [host/create-template.sh](../host/create-template.sh) :

1. télécharge `debian-13-generic-amd64.qcow2` depuis `cloud.debian.org/images/cloud/trixie/latest/` ;
2. **vérifie la somme SHA-512** avec le fichier `SHA512SUMS` officiel ;
3. installe `qemu-guest-agent` **dans l'image** avec `virt-customize` (paquet `libguestfs-tools`, installé si absent) et vide `/etc/machine-id` (chaque clone en génère un nouveau) ;
4. crée la VM 9000 : CPU `host`, `virtio-scsi-single`, carte réseau sur `vmbr1`, agent activé, **console série** (`--serial0 socket --vga serial0`) ;
5. importe le disque, ajoute le lecteur cloud-init (`ide2`), règle le démarrage sur `scsi0` ;
6. convertit la VM en template (`qm template 9000`).

**Vérifier**

```bash
qm config 9000 | grep -E 'template|agent|ide2|scsi0|serial0'
# template: 1 / agent: enabled=1 / ide2: ...cloudinit / scsi0: ... / serial0: socket
```

Dans l'interface Proxmox, la VM 9000 a l'icône de template.

**Pièges**

- `virt-customize` échoue sur le réseau : il lance une mini-VM qui doit atteindre les dépôts Debian. Vérifie que l'hôte sort bien sur Internet (`apt update` marche).
- Pas de console série : les images cloud Debian l'attendent. Sans elle, redimensionner le disque peut finir en *kernel panic* au démarrage (problème connu du provider bpg/proxmox).
- Tu relances le script : il refuse si la VM 9000 existe. `qm destroy 9000` d'abord, ou `VMID=9001`.

Suite : [étape 6 : un utilisateur et un token pour OpenTofu](06-utilisateur-token-api.md).
