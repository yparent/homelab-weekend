# Aller plus loin

Des exercices pour les week-ends suivants. Chacun réutilise le socle.

## GitOps avec Argo CD

Aujourd'hui, tu fais `kubectl apply` à la main. En GitOps, le cluster se synchronise tout seul sur le dépôt.

- Installe Argo CD dans k3s (chart Helm officiel), exposé en NodePort sur l'IP privée.
- Crée une `Application` qui pointe vers `kubernetes/demo-app/` de ton dépôt.
- Refais les pannes de l'[étape 12](12-casser-une-app.md) **par un commit** : le cluster suit Git, et `git revert` répare.
- Bonus : kube-prometheus-stack géré par Argo CD, avec les values du dépôt.

## PRA : sauvegarder et restaurer

- Installe Proxmox Backup Server sur une 2e petite machine (ou dans une VM de test pour comprendre), planifie une sauvegarde des 3 VMs.
- Exercice : supprime `lab-vm2` dans Proxmox, restaure-la depuis la sauvegarde. Chronomètre.
- Côté Kubernetes : Velero vers un stockage S3 compatible. Supprime le namespace `demo`, restaure-le.
- Compare avec la reconstruction depuis Git (`tofu apply` + Ansible). Qu'est-ce qui **doit** être sauvegardé, et qu'est-ce qui se reconstruit ?

## Les logs avec Loki

- Installe Loki (mode monolithique) et Alloy pour collecter les logs des pods.
- Ajoute la source Loki dans Grafana. Retrouve le message `FATAL ... APP_MESSAGE` de la panne 3 sans `kubectl logs`.
- Ajoute le toolset Loki à HolmesGPT (`grafana/loki`) pour que l'IA lise aussi les logs historiques.

## Exercice de migration VMware vers Proxmox

Le sujet du moment pour beaucoup d'équipes.

- Prends une appliance OVA ou un disque VMDK de test (une VM Linux exportée depuis un ESXi, ou une image publique au format VMDK).
- Importe-la : `qm importovf` pour un OVF, ou `qm disk import <vmid> disque.vmdk <stockage>` pour un disque seul. Proxmox VE 9 a aussi un assistant d'import depuis ESXi dans l'interface (*Datacenter > Storage > Add > ESXi*).
- Points de vigilance à documenter : pilotes VirtIO (disque et réseau), nom de l'interface réseau qui change, VMware Tools à désinstaller, `qemu-guest-agent` à installer, firmware BIOS/UEFI à garder identique.
- Écris le runbook de migration dans `docs/` : c'est exactement ce qu'on te demandera en mission.

## Préparer la CKA

Ton cluster k3s est un bon terrain, avec ses limites : la CKA utilise kubeadm.

- Ajoute 2 VMs dans `opentofu/variables.tf` (`lab-vm4`, `lab-vm5`), écris un rôle Ansible `kubeadm` : 1 control plane + 2 workers.
- Entraîne-toi sur : mise à jour du cluster avec kubeadm, sauvegarde/restauration etcd, NetworkPolicy, RBAC, dépannage d'un kubelet arrêté, PersistentVolume.
- Chronomètre-toi : l'examen est pratique et minuté.

## Durcir et industrialiser

- **State distant chiffré** : backend S3 (Hetzner ou OVH Object Storage) + chiffrement natif du state d'OpenTofu (bloc `encryption`, clé dérivée d'une phrase de passe ou d'un KMS).
- **Certificats** : ACME dans Proxmox sur le nom MagicDNS, puis `PROXMOX_VE_INSECURE=false`.
- **Notifications Alertmanager** : un `receiver` webhook vers ntfy, Slack ou Matrix.
- **Secrets Kubernetes** : chiffrement des secrets au repos dans k3s (`secrets-encryption: true`), puis SOPS + Argo CD, ou External Secrets.
- **Images** : remplace l'image Python publique par une image construite et scannée par ta CI (Trivy en mode `image`), poussée sur GHCR.
- **Tailscale ACL** : restreins qui peut atteindre `10.10.10.0/24` et sur quels ports, et ajoute un `autoApprovers` pour la route.
