# Samedi 7/9 : 3 VMs avec OpenTofu

Tu décris les VMs dans des fichiers texte. OpenTofu compare avec ce qui existe, et fait la différence. Plus de clics.

## Ce qu'il y a dans `opentofu/`

| Fichier | Rôle |
|---|---|
| `versions.tf` | versions **épinglées** : OpenTofu ≥ 1.13, `bpg/proxmox` 0.123.1, `hashicorp/local` 2.9.1. Backend local, chemin donné à l'init. |
| `.terraform.lock.hcl` | sommes de contrôle des providers (Linux, macOS, Windows). Commité. |
| `providers.tf` | `provider "proxmox" {}` : **aucun secret**, tout vient des variables d'environnement `PROXMOX_VE_*`. |
| `variables.tf` | nœud, stockage, template, réseau, ta clé SSH, et la carte des 3 VMs. Deux validations : la VM k3s a au moins 8 Go, pas deux VMs sur la même IP. |
| `main.tf` | une ressource `proxmox_virtual_environment_vm` avec `for_each` : clone complet du template 9000, CPU, RAM, disque, réseau `vmbr1`, console série, cloud-init (IP fixe, passerelle, DNS, utilisateur + clé SSH). |
| `inventory.tf` | écrit `ansible/inventory/hosts.yml` à partir des VMs créées. |
| `outputs.tf` | IPs, commandes SSH, IP du serveur k3s. |

Les 3 VMs par défaut :

| VM | VMID | IP | vCPU | RAM | Disque | Groupes Ansible |
|---|---|---|---|---|---|---|
| lab-vm1 | 101 | 10.10.10.11 | 2 | 4 Go | 20 Go | lab |
| lab-vm2 | 102 | 10.10.10.12 | 2 | 4 Go | 20 Go | lab |
| lab-vm3 | 103 | 10.10.10.13 | 4 | 8 Go | 40 Go | lab, k3s_server |

## 7.1 Configurer

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars   # nœud, stockage (local / local-zfs), clé SSH
cp backend.hcl.example backend.hcl             # chemin ABSOLU du state, hors du dépôt
mkdir -p ~/.homelab-state
```

Les deux fichiers sont ignorés par Git.

## 7.2 Initialiser

```bash
tofu init -backend-config=backend.hcl
```

**Vérifier** : `OpenTofu has been successfully initialized!`, avec `bpg/proxmox v0.123.1` et `hashicorp/local v2.9.1` dans la liste des providers installés.

## 7.3 Planifier puis appliquer

Les identifiants viennent du fichier chiffré par sops (étape 9). Si tu ne l'as pas encore fait, fais l'étape 9 maintenant, puis reviens.

```bash
sops exec-env ../secrets/tofu.enc.env 'tofu plan'
sops exec-env ../secrets/tofu.enc.env 'tofu apply'
# ou, depuis la racine du dépôt : make plan / make apply
```

`tofu plan` doit annoncer `4 to add` (3 VMs + le fichier d'inventaire). Lis-le avant de taper `yes`.

**Vérifier**

```bash
tofu output vm_ips
cat ../ansible/inventory/hosts.yml
ssh debian@10.10.10.11 'hostname; ip -br addr; systemctl is-active qemu-guest-agent'
```

Dans Proxmox, les 3 VMs tournent, avec les tags `homelab` et `opentofu`, et leur IP s'affiche dans l'onglet *Summary* (c'est l'agent invité qui la remonte).

## Pièges

- **`tofu apply` attend 15 minutes sur « Still creating... »** : le provider attend l'agent invité. Soit `qemu-guest-agent` n'est pas dans le template (étape 5), soit cloud-init a échoué (image `genericcloud` ?). Regarde la console de la VM dans Proxmox.
- `can't lock file '/var/lock/qemu-server/lock-9000.conf' - got timeout` : trop de clones en parallèle. `tofu apply -parallelism=1`.
- `ssh: connect to host 10.10.10.11 port 22: Operation timed out` : route Tailscale non approuvée ou `--accept-routes` manquant (étape 4).
- `403 Permission check failed` : un privilège manque au rôle (étape 6).
- Tu modifies une VM à la main dans l'interface : au prochain `tofu plan`, OpenTofu propose de revenir à ce qui est écrit. C'est voulu. Le code est la référence.

Suite : [étape 8 : Ansible](08-ansible-configuration.md).
