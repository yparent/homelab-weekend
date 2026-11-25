# Samedi 6/9 : un utilisateur dédié et un token d'API

OpenTofu parle à l'API Proxmox. Il lui faut une identité. Jamais `root@pam` dans le code : si le token fuite, c'est tout le serveur qui part.

## Ce que tu fais

```bash
bash /root/host/create-tofu-user.sh
```

Le script [host/create-tofu-user.sh](../host/create-tofu-user.sh) crée :

- un rôle `HomelabTofu` avec **uniquement** les droits utiles ici :
  `Datastore.AllocateSpace`, `Datastore.Audit`, `SDN.Audit`, `SDN.Use`, `Sys.Audit`, `VM.Allocate`, `VM.Audit`, `VM.Clone`, `VM.Config.CDROM`, `VM.Config.Cloudinit`, `VM.Config.CPU`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.GuestAgent.Audit`, `VM.PowerMgmt` ;
- un utilisateur `tofu@pve` **sans mot de passe** (il ne sert qu'à porter le token) ;
- l'ACL `/` → `tofu@pve` → `HomelabTofu` ;
- le token `tofu@pve!homelab` avec `--privsep 0` : il a exactement les droits de l'utilisateur.

Pas de `Sys.Modify`, pas de `Permissions.Modify`, pas de `User.Modify` : le token ne peut ni toucher au réseau de l'hôte, ni créer des utilisateurs, ni s'ajouter des droits.

Le secret du token s'affiche **une seule fois**. Copie-le directement dans ton fichier de secrets chiffré (étape 9). La valeur complète a la forme :

```text
tofu@pve!homelab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Vérifier

```bash
pveum user permissions tofu@pve --path /vms
pveum user token list tofu@pve
```

Et depuis ton laptop (via Tailscale) :

```bash
curl -sk -H 'Authorization: PVEAPIToken=tofu@pve!homelab=<secret>' \
  https://10.10.10.1:8006/api2/json/nodes | jq '.data[].node'
```

(Guillemets simples : dans un shell interactif, `!homelab` entre guillemets doubles déclenche l'historique de bash.)

La commande affiche le nom du nœud (souvent `pve`). Note-le pour `proxmox_node` dans OpenTofu.

## Pièges

- Proxmox VE 9 a changé la liste des privilèges : `VM.Monitor` n'existe plus. L'agent invité se lit avec `VM.GuestAgent.Audit`. Un vieux tutoriel 8.x te fera échouer `pveum role add`.
- Sans `SDN.Use`, la création de la carte réseau sur `vmbr1` est refusée (`403 Permission check failed`). Sans `SDN.Audit`, le provider ne voit pas les ponts.
- `403 Permission check failed` sur une autre action : lis le chemin et le privilège manquant dans le message, ajoute-le au rôle (`pveum role modify HomelabTofu --privs "..."` avec la liste complète), et note-le dans le script.
- Certaines options restent réservées à `root@pam` (passthrough PCI, `cpu.affinity`, `initialization.upgrade`, hugepages). Ce dépôt n'en utilise aucune. Si tu en ajoutes, attends-toi à un refus.

Suite : [étape 7 : 3 VMs avec OpenTofu](07-opentofu-vms.md).
