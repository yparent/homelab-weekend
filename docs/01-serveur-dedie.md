# Samedi 1/9 : louer un serveur dédié (pas un VPS)

## Pourquoi un dédié

Un VPS est déjà une machine virtuelle. La plupart n'exposent pas la virtualisation imbriquée : Proxmox s'installe, mais refuse de démarrer une VM (`KVM virtualisation configured, but not available`). Hetzner Cloud le dit noir sur blanc dans sa FAQ : la virtualisation imbriquée n'y est pas possible.

Il te faut une machine physique avec :

- **32 Go de RAM minimum** (3 VM : 4 + 4 + 8 Go, plus l'hôte) ;
- du **NVMe** de préférence (les clones et k3s seront bien plus rapides) ;
- un CPU qui expose **VT-x (Intel) ou AMD-V (AMD)**. Évite les vieux **Athlon** de l'enchère Hetzner.

## Option A : Hetzner Server Auction

**Ce que tu fais**

1. Va sur [hetzner.com/sb](https://www.hetzner.com/sb).
2. Filtre : RAM ≥ 32 Go (64 Go si le prix le permet), disque NVMe, CPU Intel Xeon / Core i7 ou AMD Ryzen. Exclus les Athlon.
3. Commande. Pas de frais de mise en service sur l'enchère. La facturation est à l'heure, plafonnée au prix mensuel.
4. Attends le mail de livraison avec l'IP publique.

**Budget** (vérifié le 25/11/2026) : Hetzner a augmenté ses prix plusieurs fois en 2026 (pénurie de RAM et de NVMe). La page de l'enchère affichait des serveurs « à partir de 80,70 € HT/mois ». Pour un week-end, compte le prix horaire affiché × le nombre d'heures. Exemple : 80,70 € / 730 h ≈ 0,11 € HT/h, soit environ 6 € HT pour 55 h.

## Option B : OVHcloud Eco / Kimsufi (en France)

**Ce que tu fais** : sur [eco.ovhcloud.com/fr/kimsufi](https://eco.ovhcloud.com/fr/kimsufi/), prends un **KS-B** (Xeon E5-1620v2, 32 Go DDR3 ECC) s'il est en stock.

**Ce qui change par rapport à Hetzner** (vérifié le 25/11/2026) :

- facturation **au mois**, pas à l'heure : 9,99 € HT/mois + **9,99 € HT de frais d'installation** (offerts avec un engagement de 12 mois) ;
- disque **SSD SATA de 120 Go**, pas du NVMe. Ça suffit pour 3 VM (20 + 20 + 40 Go), sans marge ;
- stock très variable : la page affichait « Prochainement disponible » ce jour-là.

## Vérifier AVANT d'installer quoi que ce soit

Connecte-toi au serveur (système rescue chez Hetzner, ou l'OS livré chez OVH) et lance le script de contrôle :

```bash
scp host/00-check-virtualization.sh root@<IP-publique>:/root/
ssh root@<IP-publique> 'bash /root/00-check-virtualization.sh'
```

Il vérifie les flags `vmx`/`svm` dans `/proc/cpuinfo`, que tu n'es pas dans une VM, la RAM et les disques. À la main :

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo   # doit être > 0
systemd-detect-virt                  # doit répondre "none"
# Sur Debian/Ubuntu : apt install cpu-checker && kvm-ok
```

**Vérifier** : la dernière ligne du script dit `machine adaptee`.

**Pièges**

- `vmx`/`svm` absents : annule tout de suite. Chez Hetzner, la facturation horaire limite la casse.
- `systemd-detect-virt` répond `kvm` ou `vmware` : tu as loué un VPS, pas un dédié.
- **Le serveur est facturé tant qu'il est dans ton compte, allumé ou éteint.** L'éteindre ne coûte pas moins. Seule la résiliation arrête la facture (voir [dimanche soir](15-nettoyage-dimanche-soir.md)).

Suite : [étape 2 : installer Proxmox VE](02-installer-proxmox.md).
