# Samedi 2/9 : installer Proxmox VE 9.2

Proxmox VE 9.2 (sortie le 21 mai 2026) est la version courante au 25/11/2026. Elle repose sur Debian 13 « Trixie ».

> **Avant tout** : garde un accès de secours ouvert. Chez Hetzner, la console Robot (onglet *Rescue* + *Reset*). Chez OVH, le mode rescue et la console IPMI/KVM. Une ligne fausse dans `/etc/network/interfaces` = plus de réseau = rescue.

## Option OVH : le gabarit du catalogue

**Ce que tu fais** : espace client OVH > ton serveur > *Réinstaller* > **Proxmox VE 9**. Ajoute ta clé SSH. Garde le partitionnement proposé (le gabarit active ZFS par défaut pour la partition de données).

Une fois installé, mets à jour vers la dernière 9.x :

```bash
ssh root@<IP-publique>
apt update && apt full-upgrade -y
pveversion
```

**Vérifier** : `pveversion` affiche `pve-manager/9.2...`. `ip -br addr` montre `vmbr0` avec ton IP publique.

**Piège** : ne touche pas à `vmbr0` créé par OVH. Tu ajoutes seulement `vmbr1` à l'étape 4.

## Option Hetzner : Debian 13, puis Proxmox par-dessus

Proxmox n'est pas dans `installimage`. La procédure : rescue → Debian 13 → paquets Proxmox, en suivant le wiki officiel [Install Proxmox VE on Debian 13 Trixie](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie).

### 2.1 Debian 13 avec installimage

1. Robot > ton serveur > *Rescue* > *Linux 64 bit* + ta clé SSH > *Activate rescue system*. Puis *Reset* > *Execute an automatic hardware reset*.
2. `ssh root@<IP-publique>` : tu es dans le rescue. Lance `bash 00-check-virtualization.sh` si ce n'est pas déjà fait.
3. Lance `installimage`, choisis **Debian**, puis la ligne **Debian-13xx-trixie-amd64-base** la plus récente. Un éditeur s'ouvre. Ne modifie que ceci :

```text
# deux disques NVMe : RAID 1 logiciel (un seul disque : SWRAID 0)
SWRAID 1
SWRAIDLEVEL 1

HOSTNAME pve.homelab.lan

# garde la ligne "PART /boot/efi esp 256M" si installimage l'a mise (serveurs UEFI)
PART swap   swap  4G
PART /boot  ext3  1024M
PART /      ext4  all
```

4. Enregistre (F10 dans mcedit), confirme, attends ~5 min, puis `reboot`.
5. Sur ton laptop : `ssh-keygen -R <IP-publique>` (la clé d'hôte a changé), puis `ssh root@<IP-publique>`.

**Vérifier** : `cat /etc/os-release` affiche Debian 13 (trixie).

### 2.2 Noter la configuration réseau actuelle

```bash
ip -br link                 # nom de la carte : enp0s31f6, eno1, enp7s0...
ip -4 addr                  # IP publique
ip route                    # passerelle par défaut
ls /etc/systemd/network/ ; cat /etc/network/interfaces
```

Garde ces valeurs dans un fichier sur ton laptop. Tu en as besoin juste après.

### 2.3 Le nom d'hôte doit pointer vers l'IP publique

Proxmox refuse de démarrer correctement si `hostname --ip-address` répond `127.0.1.1`. Édite `/etc/hosts` :

```text
127.0.0.1       localhost
203.0.113.10    pve.homelab.lan pve
```

(Remplace par ton IP, et retire `pve` de la ligne `127.0.1.1` si elle existe.)

**Vérifier** : `hostname --ip-address` affiche ton IP publique.

### 2.4 Phase 1 : dépôt Proxmox + noyau Proxmox

```bash
scp host/install-proxmox-on-debian13.sh root@<IP-publique>:/root/
ssh root@<IP-publique>
bash /root/install-proxmox-on-debian13.sh phase1
systemctl reboot
```

Le script ajoute le dépôt `pve-no-subscription` (format deb822), télécharge la clé `proxmox-archive-keyring-trixie.gpg`, **vérifie son empreinte SHA-256** publiée sur le wiki, puis installe `proxmox-default-kernel`.

**Vérifier** : après le redémarrage, `uname -r` se termine par `-pve`.

### 2.5 Passer le réseau sur /etc/network/interfaces

Proxmox utilise `ifupdown2`, qui lit `/etc/network/interfaces`. Chez Hetzner, installimage configure souvent le réseau avec `systemd-networkd` (fichiers dans `/etc/systemd/network/`). Si c'est ton cas, au prochain redémarrage le serveur reviendra **sans réseau**.

**Ce que tu fais** : écris `/etc/network/interfaces` à partir de [host/network/interfaces.hetzner.example](../host/network/interfaces.hetzner.example), avec tes valeurs notées en 2.2 (nom de carte, IP en `/32`, passerelle). Laisse le bloc `vmbr1` pour l'étape 4 (tu peux déjà le mettre, il ne gêne pas).

**Vérifier** : `grep gateway /etc/network/interfaces` affiche ta passerelle.

### 2.6 Phase 2 : les paquets Proxmox

```bash
bash /root/install-proxmox-on-debian13.sh phase2
```

Le script refuse de continuer si `/etc/network/interfaces` n'a pas de passerelle. Il installe `proxmox-ve postfix open-iscsi chrony` (postfix en « Local only »), retire le noyau Debian et `os-prober`, et désactive les dépôts *enterprise* (ils répondent 401 sans abonnement).

Si `systemd-networkd` était actif, désactive-le **avant** de redémarrer :

```bash
systemctl disable systemd-networkd.service systemd-networkd.socket
mv /etc/systemd/network/*.network /root/   # garde une copie
systemctl reboot
```

**Vérifier**

```bash
pveversion                     # pve-manager/9.2...
systemctl is-active pveproxy   # active
ip -br addr                    # ton IP publique sur la carte physique
```

Puis ouvre `https://<IP-publique>:8006` (utilisateur `root`, realm *Linux PAM*). C'est la **seule** fois où tu passes par l'IP publique : à l'étape 3, tu fermes ce port.

**Pièges**

- Le serveur ne revient pas après le redémarrage : Robot > *Rescue* > *Reset*, puis dans le rescue : `mdadm --assemble --scan`, `mount /dev/md2 /mnt` (vérifie avec `lsblk` lequel est `/`), corrige `/mnt/etc/network/interfaces`, `umount /mnt`, `reboot`.
- `ipcc_send_rec[1] failed` dans les logs : `/etc/hosts` est faux (étape 2.3).
- Secure Boot activé : le noyau Proxmox refuse de démarrer (`bad shim signature`). Désactive-le.
- OVH et Proxmox 9.2 : si tu as installé Proxmox toi-même (sans le gabarit OVH) avec ZFS ou BTRFS sur `/`, le serveur peut démarrer sur memtest86+. Voir les *Known Issues* 9.2 du [Roadmap Proxmox](https://pve.proxmox.com/wiki/Roadmap). Le gabarit OVH n'est pas concerné.

Suite : [étape 3 : verrouiller la porte](03-verrouiller-acces.md).
