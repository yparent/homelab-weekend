# Dimanche 6/6 : dimanche soir, on range

Ton infra est dans Git. Le serveur ne sert plus à rien jusqu'au prochain week-end, et il coûte tant qu'il est dans ton compte.

## 15.1 Détruire les VMs

```bash
make destroy                  # sops exec-env ../secrets/tofu.enc.env 'tofu destroy'
```

**Vérifier** : `tofu -chdir=opentofu state list` est vide (après `tofu init`), et l'interface Proxmox ne montre plus que le template 9000.

## 15.2 Résilier le serveur

**Hetzner** : Robot > *Servers* > ton serveur > *Cancellation* > résiliation **immédiate** (pour l'enchère, la résiliation est en général immédiate). Vérifie que les options éventuelles (IP supplémentaire...) sont résiliées aussi : elles se résilient séparément.

**OVH (Kimsufi)** : espace client > ton serveur > *Résilier*. Facturation au mois : la résiliation prend effet à la fin de la période payée.

**Vérifier** : le serveur n'apparaît plus (ou apparaît « résilié ») dans la console, et aucune ligne ne reste sur la prochaine facture.

**Piège** : éteindre le serveur ne suffit pas. Il est facturé allumé ou éteint, tant qu'il existe dans ton compte.

## 15.3 Nettoyer ton laptop et le tailnet

```bash
make forget-hostkeys
for ip in 10.10.10.11 10.10.10.12 10.10.10.13; do ssh-keygen -R "$ip"; done
rm -f kubeconfig/homelab.yaml kubeconfig/homelab-ai-readonly.yaml
```

Console Tailscale > *Machines* > supprime le serveur. La route `10.10.10.0/24` disparaît avec lui.

Révoque aussi le token Proxmox (il meurt avec le serveur, mais garde le réflexe) et, si tu ne t'en sers plus, la clé d'API IA.

## 15.4 Le week-end prochain

Nouveau serveur, mêmes commandes :

1. étapes 1 à 6 du samedi (hôte : Proxmox, Tailscale, pare-feu, `vmbr1`, template, token) ;
2. mets à jour `secrets/tofu.enc.env` avec le nouveau token : `sops edit secrets/tofu.enc.env` ;
3. puis :

```bash
make init
make weekend-up        # VMs, Ansible, k3s, monitoring, alertes, app de démo
```

## 15.5 Rendre le dépôt public

Ton dépôt est un portfolio : il montre ce que tu sais faire, en code, avec une CI verte.

**Avant de le passer public :**

```bash
git log --all -p | grep -nE 'PVEAPIToken|PROXMOX_VE_API_TOKEN=[^0]|sk-ant-|sk-[A-Za-z0-9]{20}|BEGIN (OPENSSH|RSA) PRIVATE' || echo "rien de suspect"
git ls-files | grep -E 'tfstate|tfvars$|backend.hcl$|kubeconfig|keys.txt' || echo "aucun fichier sensible suivi"
```

Si un secret apparaît : révoque-le d'abord, nettoie l'historique ensuite.

Puis GitHub > *Settings* > *General* > *Danger Zone* > *Change visibility* > *Public*. Active *Secret scanning* et *Push protection* (*Settings* > *Code security*).

Soigne le README : ce que fait le projet, le schéma, les choix (dédié plutôt que VPS, NAT + Tailscale, IA en lecture seule), et ce que tu ferais ensuite. Un recruteur lit ça en deux minutes.

Pour la suite : [aller plus loin](aller-plus-loin.md).
