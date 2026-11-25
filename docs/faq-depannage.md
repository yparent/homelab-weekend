# FAQ et dépannage

Classé par étape. Pour chaque symptôme : la cause probable, puis la commande qui le confirme.

## Le serveur

**Proxmox s'installe, mais la VM refuse de démarrer : `KVM virtualisation configured, but not available`.**
Tu es sur un VPS, ou le CPU n'expose pas la virtualisation. `systemd-detect-virt` (doit répondre `none`) et `grep -Ec '(vmx|svm)' /proc/cpuinfo` (doit être > 0). Sur un PC maison : active VT-x / AMD-V (SVM) dans le BIOS. Sur un VPS : rien à faire, change d'offre. Hetzner Cloud ne propose pas de virtualisation imbriquée.

**J'ai éteint le serveur, je paie quand même.**
Normal. Facturé tant qu'il est dans ton compte. Résilie-le ([étape 15](15-nettoyage-dimanche-soir.md)).

## Réseau et accès

**Plus d'accès après un redémarrage (Hetzner).**
Presque toujours `/etc/network/interfaces` : mauvais nom de carte, mauvaise passerelle, ou `systemd-networkd` désactivé sans fichier `interfaces` valide. Robot > *Rescue* > *Reset*, puis dans le rescue :

```bash
mdadm --assemble --scan
lsblk                         # repère l'array de / (souvent md2)
mount /dev/md2 /mnt
nano /mnt/etc/network/interfaces
umount /mnt && reboot
```

**Je me suis enfermé dehors avec le pare-feu.**
Si tu as utilisé `apply-with-rollback.sh`, attends 5 minutes. Sinon : console KVM / rescue, puis `nft delete table inet homelab` et `systemctl disable homelab-firewall`.

**`ssh 10.10.10.11` : timeout.**
Dans l'ordre :

1. `tailscale status` : l'hôte est en ligne ?
2. console Tailscale : la route `10.10.10.0/24` est-elle **approuvée** ?
3. laptop Linux : `tailscale debug prefs | grep -i routeall` doit être `true` (sinon `sudo tailscale set --accept-routes`) ;
4. `ping 10.10.10.1` (l'hôte) marche, mais pas `10.10.10.11` : la VM est-elle démarrée ? cloud-init a-t-il posé l'IP (console Proxmox) ?
5. conflit : ton réseau local utilise déjà `10.10.10.0/24` (`ip route` / `netstat -rn`).

**Les VMs n'ont pas Internet (`apt update` bloqué).**
NAT ou routage. Sur l'hôte : `sysctl net.ipv4.ip_forward` (= 1), `nft list chain inet homelab postrouting` (règle `masquerade`), et `define WAN` correspond bien à ta carte (`ip -br link`). Dans la VM : `ip route` montre `default via 10.10.10.1`, `resolvectl status` ou `cat /etc/resolv.conf` montre les DNS.

**Tailscale passe par un relais (lent).**
`tailscale ping <hôte>` affiche `via DERP`. Vérifie l'ouverture du port UDP 41641 dans `homelab.nft` (et dans le pare-feu Robot si tu l'utilises).

## Template et cloud-init

**La VM démarre sans mon utilisateur / sans IP.**
Image `genericcloud` au lieu de `generic` : le noyau allégé ne voit pas le lecteur cloud-init IDE. Refais le template avec `debian-13-generic-amd64.qcow2`. Pour confirmer : console de la VM, `sudo cloud-init status --long`.

**`tofu apply` reste 15 minutes sur « Still creating... ».**
Le provider attend `qemu-guest-agent`. Vérifie dans la VM : `systemctl status qemu-guest-agent`. Absent : le template n'a pas l'agent (refais l'étape 5).

**Kernel panic au démarrage après redimensionnement du disque.**
Pas de console série. Le template doit avoir `serial0: socket` et la VM un bloc `serial_device { device = "socket" }` (déjà dans `main.tf`).

## OpenTofu et Proxmox

**`403 Permission check failed (/vms/101, VM.Config.Cloudinit)`** (ou autre privilège).
Le rôle `HomelabTofu` n'a pas ce droit. Ajoute-le dans `host/create-tofu-user.sh`, relance le script (il met le rôle à jour). Vérifie avec `pveum user permissions tofu@pve --path /vms`.

**`401 authentication failure`.**
Token mal recopié. Format exact : `tofu@pve!homelab=<uuid>`. Teste avec `curl` ([étape 6](06-utilisateur-token-api.md)).

**`x509: certificate signed by unknown authority`.**
Certificat auto-signé de Proxmox. `PROXMOX_VE_INSECURE=true` dans `secrets/tofu.enc.env`. Mieux, plus tard : un vrai certificat (ACME) sur le nom Tailscale.

**`can't lock file '/var/lock/qemu-server/lock-9000.conf' - got timeout`.**
Trop de clones en parallèle. `tofu apply -parallelism=1`.

**`tofu plan` veut tout recréer après un changement de template.**
Normal : le template est une source de clone. Changer `template_vm_id` = nouvelles VMs.

**J'ai perdu le state.**
OpenTofu ne connaît plus les VMs. Supprime-les dans Proxmox (`qm destroy 101` etc.), puis `tofu apply`. Ou importe-les (`tofu import 'proxmox_virtual_environment_vm.lab["lab-vm1"]' pve/101`). Leçon : sauvegarde le state.

## Ansible

**`Could not get lock /var/lib/dpkg/lock-frontend`.**
cloud-init travaille encore. Le rôle `common` attend `cloud-init status --wait` ; relance simplement le playbook.

**`REMOTE HOST IDENTIFICATION HAS CHANGED`.**
VMs reconstruites, nouvelles clés d'hôte. `make forget-hostkeys` (et `ssh-keygen -R <ip>` pour tes `ssh` manuels).

**`ansible` ignore `ansible.cfg`.**
Lance les commandes depuis le dossier `ansible/`. Ansible ignore aussi un `ansible.cfg` situé dans un dossier accessible en écriture à tous (`chmod o-w ansible`).

## k3s et Kubernetes

**Pods `Pending`, `OOMKilled`, nœud `MemoryPressure`.**
La VM 3 manque de RAM. `kubectl top nodes`, `kubectl describe node lab-vm3`. Il faut 8 Go minimum avec la stack de monitoring.

**`x509: certificate is valid for 127.0.0.1, not 10.10.10.13`.**
`tls-san` absent lors de la première installation. Voir [étape 10](10-k3s.md).

**`no matches for kind "PrometheusRule"`.**
CRD absente : installe kube-prometheus-stack avant d'appliquer `homelab-alerts.yaml`.

**Mise à jour majeure du chart : erreurs sur les CRDs.**
Helm n'installe les CRDs qu'au premier `install`, jamais en `upgrade`. Applique les nouvelles CRDs à la main avec `kubectl apply --server-side`, comme indiqué dans les notes de version du chart. Le mode `--server-side` évite `metadata.annotations: Too long`.

**Alerte `TargetDown` permanente pour kube-controller-manager / scheduler / proxy / etcd.**
k3s n'expose pas ces métriques par défaut. Déjà désactivé dans les values ; si tu les as réactivés, recoupe-les.

**Les 3 cibles node-exporter sont DOWN dans Prometheus.**
`curl http://10.10.10.11:9100/metrics` depuis ton laptop. S'il répond, le problème est côté cluster (logs de Prometheus). Sinon : `systemctl status node_exporter` dans la VM.

## IA

**HolmesGPT : `pipx install` échoue.**
Python 3.14 par défaut. `pipx install --python python3.13 holmesgpt`.

**HolmesGPT ou K8sGPT voient des `Forbidden`.**
C'est le kubeconfig lecture seule qui fait son travail. Si l'outil a vraiment besoin d'une lecture légitime (une ressource absente de la liste), ajoute-la au ClusterRole en `get/list/watch`. Jamais `secrets`, jamais d'écriture.

**Le jeton du kubeconfig IA a expiré (`Unauthorized`).**
`make ai-readonly` en refait un (8 h).
