# Samedi 8/9 : configurer les VMs avec Ansible

OpenTofu crée les machines. Ansible les configure. Chacun son métier.

## Ce qu'il y a dans `ansible/`

| Élément | Rôle |
|---|---|
| `ansible.cfg` | inventaire, rôles, et un fichier `known_hosts` **dédié** (`ansible/.known_hosts`, ignoré par Git) |
| `inventory/hosts.yml` | généré par OpenTofu (exemple : `hosts.example.yml`) |
| `inventory/group_vars/all.yml` | versions épinglées : node_exporter 1.13.1, k3s v1.37.2+k3s1 |
| `roles/common` | attend la fin de cloud-init, mises à jour complètes, mises à jour de sécurité automatiques, durcissement SSH, redémarrage si un nouveau noyau l'exige |
| `roles/node_exporter` | utilisateur système, binaire officiel **vérifié par SHA-256**, service systemd durci, écoute sur l'IP privée uniquement |
| `roles/k3s` | dimanche ([étape 10](10-k3s.md)) |
| `playbooks/base.yml` | `common` + `node_exporter` sur le groupe `lab` |

Le durcissement SSH des VMs (`/etc/ssh/sshd_config.d/10-homelab-hardening.conf`) : pas de mot de passe, pas de root, `MaxAuthTries 3`, `AllowUsers debian`. Le fichier est validé par `sshd -t` **avant** d'être mis en place : une erreur de syntaxe ne te coupe pas l'accès.

## Ce que tu fais

```bash
cd ansible        # obligatoire : ansible.cfg est lu depuis le dossier courant
ansible all -m ping
ansible-playbook playbooks/base.yml
# ou depuis la racine : make ansible
```

**Vérifier**

```bash
ansible-playbook playbooks/base.yml        # 2e passage : changed=0 partout
ssh debian@10.10.10.11 'sudo sshd -T | grep -E "^(passwordauthentication|permitrootlogin)"'
# passwordauthentication no / permitrootlogin no
curl -s http://10.10.10.11:9100/metrics | grep ^node_uname_info
```

Le deuxième passage sans changement prouve que les rôles sont idempotents : tu peux les relancer sans risque.

## Pièges

- `ansible all -m ping` répond `UNREACHABLE` : même diagnostic que SSH à l'étape 7 (route Tailscale).
- `Could not get lock /var/lib/dpkg/lock-frontend` : cloud-init installe encore des paquets au premier démarrage. Le rôle `common` attend `cloud-init status --wait`. Si tu lances des commandes `apt` à la main avant, attends.
- `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` après une reconstruction : les nouvelles VMs ont de nouvelles clés d'hôte, mêmes IPs. `make forget-hostkeys` (vide `ansible/.known_hosts`). Ton `~/.ssh/known_hosts` personnel n'est pas touché par Ansible, mais il l'est par tes `ssh` manuels : `ssh-keygen -R 10.10.10.11`.
- `ansible-lint` ou `ansible` en version trop vieille : vérifie Python ≥ 3.13 sur ton laptop ([vendredi](00-vendredi-preparation.md)).

Suite : [étape 9 : Git, state et secrets](09-git-state-secrets.md).
