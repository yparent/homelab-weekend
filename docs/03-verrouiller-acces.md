# Samedi 3/9 : verrouiller la porte d'abord

Ton serveur a une IP publique. Dans les minutes qui suivent sa livraison, des robots testent déjà le port 22. L'objectif : **plus rien d'ouvert côté Internet**, ni SSH (22) ni l'interface Proxmox (8006). Tu passes uniquement par Tailscale.

## 3.1 Tailscale sur l'hôte

```bash
scp -r host root@<IP-publique>:/root/
ssh root@<IP-publique>
bash /root/host/tailscale-setup.sh
```

Le script installe Tailscale (script officiel) et lance `tailscale up`. Ouvre l'URL affichée dans ton navigateur pour ajouter le serveur à ton tailnet.

**Vérifier** (depuis ton laptop) :

```bash
tailscale status                   # le serveur apparaît
ssh root@<IP-tailscale-du-serveur> # 100.x.y.z, ou son nom MagicDNS
```

Ouvre aussi `https://<IP-tailscale>:8006` : l'interface Proxmox doit répondre.

**Piège** : dans la console Tailscale, désactive l'expiration de clé pour ce serveur (*Machines > ... > Disable key expiry*). Sinon il sort du tailnet au bout de quelques mois, et tu n'as plus d'accès si les ports publics sont fermés.

## 3.2 SSH : clé uniquement

```bash
cp /root/host/ssh/10-homelab-hardening.conf /etc/ssh/sshd_config.d/
sshd -t && systemctl reload ssh
```

**Vérifier** :

```bash
sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication)'
# passwordauthentication no / permitrootlogin without-password / kbdinteractiveauthentication no
```

Garde ta session ouverte et teste une **nouvelle** connexion depuis un autre terminal avant de fermer la première.

**Piège** : `PermitRootLogin` reste à `prohibit-password` (affiché `without-password`). Proxmox a besoin de root en SSH pour certaines opérations internes. Clé oui, mot de passe jamais.

## 3.3 Le pare-feu (nftables) avec retour arrière automatique

Le fichier [host/firewall/homelab.nft](../host/firewall/homelab.nft) :

- bloque tout en entrée, sauf : connexions établies, `tailscale0`, le port UDP 41641 de Tailscale, l'ICMP ;
- prépare déjà le NAT des VMs pour l'étape 4.

Il utilise sa propre table (`inet homelab`) : il ne vide pas les règles de Tailscale.

**Ce que tu fais**

1. Mets le nom de ta carte réseau dans `define WAN` (Hetzner : `ip -br link` ; OVH : `vmbr0`).
2. Charge-le avec le retour arrière automatique :

```bash
mkdir -p /etc/homelab
cp /root/host/firewall/homelab.nft /etc/homelab/homelab.nft
nano /etc/homelab/homelab.nft            # define WAN = "..."
bash /root/host/firewall/apply-with-rollback.sh /etc/homelab/homelab.nft 300
```

Le script vérifie la syntaxe (`nft -c`), programme la suppression de la table dans 5 minutes, puis charge les règles. Si tu t'es enfermé dehors, attends 5 minutes : l'accès revient tout seul.

**Vérifier** (depuis ton laptop, dans un **autre** terminal) :

```bash
ssh root@<IP-tailscale>            # doit marcher
ssh -o ConnectTimeout=5 root@<IP-publique>   # doit échouer (timeout)
curl -k -m 5 https://<IP-publique>:8006      # doit échouer (timeout)
```

Si tout est bon, annule le retour arrière et rends les règles permanentes :

```bash
systemctl stop homelab-fw-rollback.timer
cp /root/host/firewall/homelab-firewall.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable homelab-firewall.service
```

**Vérifier après un redémarrage** : `nft list table inet homelab` affiche les règles.

**Pièges**

- Tailscale en relais (DERP) plutôt qu'en direct : vérifie que le port UDP 41641 est bien autorisé. `tailscale ping <serveur>` doit finir par `via <IP>:41641`.
- Hetzner propose aussi un pare-feu réseau dans Robot. Tu peux l'ajouter en deuxième couche, mais il est sans état : garde une règle qui laisse entrer les réponses TCP (flag `ack`) et UDP 41641, sinon `apt update` et Tailscale cassent.

Suite : [étape 4 : le réseau des VMs](04-reseau-vms-nat.md).
