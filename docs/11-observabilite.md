# Dimanche 2/6 : l'observabilité (Prometheus, Grafana, Alertmanager)

Tu installes **kube-prometheus-stack** (chart 93.11.0 au 25/11/2026 : Prometheus Operator v0.95.2, Prometheus v3.16.0, Alertmanager v0.35.1, Grafana 13.3.2) et tu y branches les node_exporters installés samedi par Ansible.

## Les choix dans `kubernetes/monitoring/values-kube-prometheus-stack.yaml`

- **node-exporter du chart désactivé** (`nodeExporter.enabled: false`). Le tien tourne déjà sur le port 9100 des 3 VMs. Le DaemonSet du chart voudrait le même port sur `lab-vm3`. Les tableaux de bord « Node Exporter » restent déployés (`forceDeployDashboards: true`).
- **Les 3 VMs en cibles** via `additionalScrapeConfigs`, job `node-exporter` (le nom attendu par les tableaux de bord et les règles du chart), avec `instance` renommé en `lab-vm1`, `lab-vm2`, `lab-vm3`.
- **Composants k3s non exposés désactivés** (`kubeControllerManager`, `kubeScheduler`, `kubeProxy`, `kubeEtcd`). Sinon : des alertes `TargetDown` permanentes.
- **Sélecteurs ouverts** (`ruleSelectorNilUsesHelmValues: false`, etc.) : Prometheus prend toutes les `PrometheusRule` du cluster, pas seulement celles du chart.
- **NodePort** sur l'IP privée : Prometheus `30090`, Alertmanager `30903`, Grafana `30030`. Accessibles uniquement via Tailscale.
- Rétention 2 jours, pas de volume persistant : c'est un labo du week-end.

## 11.1 Installer

```bash
export KUBECONFIG=$PWD/kubeconfig/homelab.yaml
make monitoring
```

La cible fait :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
sops exec-env secrets/lab.enc.env 'helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version 93.11.0 --namespace monitoring --create-namespace \
  -f kubernetes/monitoring/values-kube-prometheus-stack.yaml \
  --set-literal grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" --wait --timeout 10m'
```

Le mot de passe Grafana sort du fichier chiffré, jamais d'un fichier en clair.

**Vérifier**

```bash
kubectl -n monitoring get pods          # tout Running au bout de 2-3 minutes
```

Puis, dans ton navigateur (via Tailscale) :

- `http://10.10.10.13:30090/targets` : le job **node-exporter** a 3 cibles **UP** (`lab-vm1`, `lab-vm2`, `lab-vm3`) ;
- `http://10.10.10.13:30030` : Grafana (`admin` + ton mot de passe), tableau de bord *Node Exporter / Nodes*, choisis `lab-vm1`.

## 11.2 Créer une alerte

[kubernetes/monitoring/homelab-alerts.yaml](../kubernetes/monitoring/homelab-alerts.yaml) définit trois alertes :

| Alerte | Condition | Délai |
|---|---|---|
| `HomelabNodeExporterDown` | `up{job="node-exporter"} == 0` | 1 min |
| `HomelabDiskAlmostFull` | moins de 15 % libre sur `/` | 5 min |
| `HomelabPodRestartingTooOften` | plus de 3 redémarrages en 10 min dans `demo` | 1 min |

```bash
make alerts       # kubectl apply -f kubernetes/monitoring/homelab-alerts.yaml
```

**Vérifier** : `http://10.10.10.13:30090/alerts` liste le groupe `homelab.vms` avec ses règles en vert (*inactive*).

## 11.3 La déclencher

```bash
ssh debian@10.10.10.11 'sudo systemctl stop node_exporter'
```

**Vérifier**

1. `http://10.10.10.13:30090/targets` : `lab-vm1` passe **DOWN** (≤ 30 s).
2. `http://10.10.10.13:30090/alerts` : `HomelabNodeExporterDown` passe **Pending**, puis **Firing** après 1 minute.
3. `http://10.10.10.13:30903` (Alertmanager) : l'alerte apparaît avec `instance="lab-vm1"`.

En ligne de commande :

```bash
curl -s http://10.10.10.13:30903/api/v2/alerts | jq '.[].labels.alertname'
```

Puis répare :

```bash
ssh debian@10.10.10.11 'sudo systemctl start node_exporter'
```

L'alerte disparaît d'Alertmanager au cycle suivant.

## Pièges

- **Les CRDs et Helm** : Helm installe les CRDs du dossier `crds/` à l'installation, **jamais à la mise à jour**. Quand tu montes de version majeure du chart, applique d'abord les nouvelles CRDs à la main (`kubectl apply --server-side -f ...`, voir les notes de version du chart). Le `--server-side` évite l'erreur `metadata.annotations: Too long`.
- `kubectl apply -f homelab-alerts.yaml` répond `no matches for kind "PrometheusRule"` : le chart n'est pas encore installé (pas de CRD). Installe-le d'abord.
- Les 3 cibles sont DOWN : node_exporter écoute sur l'IP privée de chaque VM. Teste `curl http://10.10.10.11:9100/metrics` depuis ton laptop. Si ça répond, regarde `kubectl -n monitoring logs prometheus-kps-kube-prometheus-stack-prometheus-0 -c prometheus`.
- Le pod Prometheus redémarre en boucle (`OOMKilled`) : la VM 3 manque de RAM. Vérifie `kubectl top pods -A`.
- Aucune notification n'arrive : normal, aucun destinataire n'est configuré dans Alertmanager. L'alerte est visible dans l'interface. Ajouter un webhook, ntfy ou un mail est dans [aller plus loin](aller-plus-loin.md).

Suite : [étape 12 : casser une application](12-casser-une-app.md).
