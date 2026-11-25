# Dimanche 5/6 : une CI minimale avec GitHub Actions

À chaque `git push`, GitHub vérifie ton code. Ça tourne sur les machines de GitHub : rien n'est exposé chez toi, et la CI n'a **aucun secret** (elle ne touche pas au homelab).

## Ce que fait `.github/workflows/ci.yml`

| Job | Commandes | Ce que ça attrape |
|---|---|---|
| `opentofu` | `tofu fmt -check -recursive`, `tofu init -backend=false`, `tofu validate` | code mal formaté, erreur de syntaxe, attribut inconnu du provider |
| `ansible` | `ansible-lint` (profil `production`) | modules non qualifiés, `command` sans `changed_when`, droits de fichiers implicites, YAML douteux |
| `trivy` | `trivy config .` (HIGH et CRITICAL bloquants) | conteneurs root, privilèges, manifests Kubernetes risqués |

Versions : OpenTofu 1.13.10, ansible-core 2.22.0, ansible-lint 26.11.1, Trivy 0.76.2 (via `aquasecurity/trivy-action` 0.36.0).

**Les actions sont épinglées par SHA de commit**, pas par tag. En mars 2026, des attaquants ont réécrit les tags de `aquasecurity/trivy-action` pour voler les secrets des pipelines (CVE-2026-33634). Un tag peut être déplacé, un SHA non. Le commentaire `# v7.0.1` à côté sert à la lecture humaine.

## Ce que tu fais

1. Pousse le dépôt : le workflow démarre tout seul (onglet *Actions*).
2. Lance les mêmes vérifications en local avant de pousser :

```bash
make lint
# tofu fmt/validate, ansible-lint, yamllint, shellcheck, trivy config
```

**Vérifier** : les trois jobs sont verts dans l'onglet *Actions*.

**Tester que la CI sert à quelque chose** : casse volontairement le formatage, pousse sur une branche, ouvre une PR.

```bash
git switch -c test-ci
sed -i 's/  cores = each.value.cores/cores=each.value.cores/' opentofu/main.tf
git commit -am "test: CI doit echouer" && git push -u origin test-ci
```

Le job `opentofu` échoue sur `tofu fmt -check`. Corrige avec `tofu fmt -recursive opentofu/`, repousse : vert.

## Pièges

- `ansible-lint` échoue en CI mais pas chez toi : versions différentes. Aligne-toi sur celles du workflow.
- Ne mets **jamais** le token Proxmox ou la clé d'API dans les secrets GitHub pour « faire un `tofu plan` en CI ». Le homelab n'est pas joignable depuis GitHub, et c'est voulu.
- Pour garder les SHA à jour sans effort : active Dependabot pour `github-actions` (fichier `.github/dependabot.yml`).

Suite : [étape 15 : dimanche soir](15-nettoyage-dimanche-soir.md).
