# Samedi 9/9 : tout dans Git, le state dehors, les secrets chiffrés

Trois règles :

1. **Le code va dans Git.** Tout ce qui décrit l'infra.
2. **Le state OpenTofu reste hors du dépôt.** Il décrit ton infra réelle, avec des détails que tu ne veux pas sur GitHub.
3. **Les secrets sont chiffrés avec sops + age.** Le fichier chiffré peut être commité. La clé privée age, jamais.

## 9.1 Le state hors du dépôt

Déjà fait à l'étape 7 : `backend.hcl` pointe vers `~/.homelab-state/homelab.tfstate`.

**Vérifier**

```bash
ls ~/.homelab-state/              # homelab.tfstate
git status --ignored | grep -E 'tfstate|tfvars|backend.hcl'   # ignorés
```

**Piège** : ce fichier est ta mémoire de l'infra. Si tu le perds, OpenTofu ne sait plus que les VMs existent. Sauvegarde-le (il est petit). Plus tard, passe sur un backend S3 compatible (Hetzner Object Storage, OVH Object Storage) avec le chiffrement natif du state d'OpenTofu (voir [aller plus loin](aller-plus-loin.md)).

## 9.2 Une clé age

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt     # ta clé PUBLIQUE : age1...
```

Sauvegarde `keys.txt` dans ton gestionnaire de mots de passe. Sans elle, tes secrets chiffrés sont perdus.

**Piège macOS** : sops cherche la clé dans `~/Library/Application Support/sops/age/keys.txt`, pas dans `~/.config`. Ajoute à ton shell : `export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt`.

## 9.3 Dire à sops qui peut déchiffrer

```bash
cp .sops.yaml.example .sops.yaml
# remplace age1replace... par ta clé publique
```

La règle chiffre tout fichier `secrets/*.enc.env` ou `secrets/*.enc.yaml` pour ta clé.

## 9.4 Chiffrer les secrets

Tu remplis une copie en clair **ignorée par Git** (`secrets/*.env`), tu la chiffres vers le fichier `.enc.env`, puis tu supprimes le clair.

```bash
cp secrets/tofu.env.example secrets/tofu.env
nano secrets/tofu.env                     # le vrai token (étape 6)
sops encrypt --filename-override secrets/tofu.enc.env secrets/tofu.env > secrets/tofu.enc.env
shred -u secrets/tofu.env                 # macOS : rm -P secrets/tofu.env

cp secrets/lab.env.example secrets/lab.env
nano secrets/lab.env                      # mot de passe Grafana, clé d'API IA
sops encrypt --filename-override secrets/lab.enc.env secrets/lab.env > secrets/lab.enc.env
shred -u secrets/lab.env
```

`--filename-override` dit à sops quelle règle de `.sops.yaml` appliquer (celle des `*.enc.env`). Sans elle, sops répond `no matching creation rules found` : c'est voulu, le clair ne correspond à aucune règle.

Ensuite, tu ne recrées plus de clair : `sops edit secrets/tofu.enc.env` ouvre ton éditeur sur la version déchiffrée et rechiffre à la sauvegarde.

**Vérifier**

```bash
grep -c 'ENC\[' secrets/tofu.enc.env      # > 0 : les valeurs sont chiffrées
sops exec-env secrets/tofu.enc.env 'echo $PROXMOX_VE_ENDPOINT'
```

`sops exec-env` déchiffre en mémoire, lance la commande avec les variables, et n'écrit rien sur le disque. C'est ce qu'utilisent `make plan`, `make apply` et `make monitoring`.

## 9.5 Commiter

```bash
git add .
git status          # relis la liste : aucun .tfstate, tfvars, backend.hcl, kubeconfig, keys.txt
git commit -m "homelab: socle Proxmox + OpenTofu + Ansible"
git push
```

**Pièges**

- Tu as oublié la redirection `> secrets/...enc.env` : le résultat chiffré s'affiche à l'écran et rien n'est écrit. Vérifie toujours avec `grep ENC`.
- Un secret en clair a été poussé : le supprimer dans un nouveau commit ne suffit pas, il reste dans l'historique. **Révoque-le** (nouveau token Proxmox, nouvelle clé d'API), puis nettoie l'historique.
- Active *Secret scanning* et *Push protection* dans les réglages du dépôt GitHub. C'est gratuit pour les dépôts publics.

## Le test du samedi

Le vrai test d'un socle en code : tout détruire, tout reconstruire, sans un clic.

```bash
make destroy           # tofu destroy : les 3 VMs disparaissent
make apply             # tofu apply : elles reviennent
make forget-hostkeys
make ansible           # configurées à l'identique
# ou tout d'un coup : make rebuild
```

**Vérifier** : `ssh debian@10.10.10.11 'uptime'` montre une machine de quelques minutes, et `curl -s http://10.10.10.12:9100/metrics | head -3` répond.

**Rappel facture** : le serveur reste facturé, allumé ou éteint, tant qu'il est dans ton compte.

Suite : [dimanche, étape 1 : k3s](10-k3s.md).
