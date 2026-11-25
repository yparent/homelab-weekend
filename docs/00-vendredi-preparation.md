# Vendredi soir : la préparation (~20 min)

Le but : arriver samedi matin sans rien attendre. Le seul vrai délai, c'est la vérification d'identité chez l'hébergeur. Lance-la ce soir.

## 1. Le compte chez l'hébergeur

**Ce que tu fais**

- **Hetzner** : crée un compte sur [accounts.hetzner.com](https://accounts.hetzner.com). Pour un nouveau client, Hetzner vérifie le compte avant de livrer un serveur. Ça peut prendre de quelques minutes à plus d'une journée. Ne commande rien ce soir, ouvre juste le compte.
- **OVHcloud** (option française) : crée un compte sur [ovhcloud.com](https://www.ovhcloud.com/fr/). Regarde le stock Kimsufi KS-B ce soir : il est souvent en rupture.
- **Alternative maison** : un vieux PC avec 32 Go de RAM et un CPU avec virtualisation (VT-x / AMD-V activé dans le BIOS). Tu sautes alors l'étape 1 du samedi, et tu installes Proxmox depuis l'ISO officielle.

**Vérifier** : tu peux te connecter à la console Robot (Hetzner) ou à l'espace client OVH.

**Piège** : la carte bancaire prépayée ou une adresse incomplète bloquent souvent la validation Hetzner. Mets les vraies infos tout de suite.

## 2. La clé SSH

**Ce que tu fais**

```bash
ssh-keygen -t ed25519 -C "homelab-$(date +%Y)"
# Entrée pour le chemin par défaut (~/.ssh/id_ed25519), puis une passphrase.
cat ~/.ssh/id_ed25519.pub
```

Ajoute la clé publique (`.pub`) dans Hetzner Robot (*Key management*) ou dans l'espace client OVH.

**Vérifier** : `ls -l ~/.ssh/id_ed25519*` montre deux fichiers. La clé privée a les droits `-rw-------`.

**Piège** : tu ne colles jamais la clé **privée** nulle part. Seule la `.pub` sort de ta machine.

## 3. Le compte Tailscale

**Ce que tu fais** : crée un compte sur [tailscale.com](https://tailscale.com) (plan *Personal*, gratuit). Installe Tailscale sur ton laptop et connecte-le.

```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# macOS / Windows : l'application officielle.
```

**Vérifier** : `tailscale status` liste ton laptop.

**Piège** : sur Linux, ton laptop n'accepte pas les routes annoncées par les autres machines. Tu en auras besoin samedi : `sudo tailscale set --accept-routes`.

## 4. Le dépôt GitHub vide

**Ce que tu fais** : crée un dépôt `homelab` vide sur GitHub (sans README, tu pousseras le tien). Puis récupère ce dépôt-ci comme point de départ :

```bash
git clone https://github.com/yparent/homelab-weekend.git homelab
cd homelab
git remote set-url origin git@github.com:<ton-compte>/homelab.git
```

**Vérifier** : `git remote -v` pointe vers ton dépôt.

**Piège** : laisse-le **privé** tant que tu n'as pas vérifié qu'aucun secret en clair n'est commité (voir [étape 9](09-git-state-secrets.md)). Tu le passeras public dimanche soir.

## 5. Les outils sur ton laptop

| Outil | Version testée | Installation |
|---|---|---|
| git | toute version récente | paquet de ta distribution |
| OpenTofu | 1.13.10 | `brew install opentofu` ou [installeur officiel](https://opentofu.org/docs/intro/install/) |
| Ansible (ansible-core) | 2.22.0 | `pipx install ansible-core` puis `pipx install ansible-lint` |
| kubectl | 1.37.2 | `brew install kubectl` ou [dl.k8s.io](https://kubernetes.io/docs/tasks/tools/) |
| Helm | 4.3.2 (3.x marche aussi) | `brew install helm` |
| sops + age | 3.13.3 / 1.3.2 | `brew install sops age` ou les binaires GitHub |

```bash
tofu version && ansible --version | head -1 && kubectl version --client && helm version && sops --version && age --version
```

**Vérifier** : chaque commande répond avec un numéro de version.

**Pièges**

- ansible-core 2.22 exige **Python 3.13 ou plus** sur ton laptop. Avec un Python plus vieux, `pipx` installe une version plus ancienne sans rien dire. Vérifie avec `ansible --version`. Si besoin : `pipx install --python python3.13 ansible-core`.
- Sous Windows, travaille dans WSL2 (Ubuntu). Ansible ne tourne pas nativement sous Windows.

## 6. La clé d'API IA, avec un plafond bas

Dimanche, l'IA lira ton cluster. Elle consomme des tokens à chaque question.

**Ce que tu fais**

- **Anthropic** : dans la Claude Console, crée un *workspace* dédié `homelab`, mets-lui une limite mensuelle basse (*Settings > Spend limits > Workspace limits > Monthly spend limit*, par exemple 5 $), puis crée la clé d'API **dans ce workspace**.
- **OpenAI** : crée un projet dédié avec un budget bas, et une clé limitée à ce projet.

**Vérifier** : la limite apparaît dans la console, et la clé est rattachée au bon workspace / projet.

**Piège** : une clé créée dans le workspace par défaut n'hérite pas de ta limite `homelab`. Une boucle d'investigation mal partie peut coûter plus que prévu.

## Récap du vendredi

- [ ] Compte Hetzner ou OVH en cours de validation
- [ ] Clé SSH ed25519 créée et déclarée chez l'hébergeur
- [ ] Tailscale sur le laptop
- [ ] Dépôt GitHub `homelab` (privé pour l'instant)
- [ ] git, OpenTofu, Ansible, kubectl, helm, sops, age installés
- [ ] Clé d'API IA avec plafond

Suite : [samedi, étape 1 : le serveur dédié](01-serveur-dedie.md).
