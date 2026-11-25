# Dimanche 4/6 : l'IA en lecture seule

La règle : **l'IA propose, tu vérifies** avec `kubectl describe` et `kubectl logs`. Et pour que ce soit vrai même si l'IA (ou toi, un soir de fatigue) tape une commande dangereuse, tu lui donnes une identité qui **ne peut pas écrire**. C'est le serveur API de Kubernetes qui refuse, pas une promesse de l'outil.

## 13.1 L'identité lecture seule

[kubernetes/ai-readonly/rbac.yaml](../kubernetes/ai-readonly/rbac.yaml) crée :

- un ServiceAccount `ai-readonly` ;
- un ClusterRole avec uniquement `get`, `list`, `watch` sur les pods, leurs logs, les événements, les déploiements, les services, les nœuds, les ConfigMaps, les objets de monitoring... ;
- **pas** de `secrets`, pas de `pods/exec`, pas de `pods/portforward`, aucun verbe d'écriture.

```bash
make ai-readonly
# = kubectl apply -f kubernetes/ai-readonly/rbac.yaml
#   + bash kubernetes/ai-readonly/make-readonly-kubeconfig.sh
```

Le script fabrique `kubeconfig/homelab-ai-readonly.yaml` avec un **jeton court** (`kubectl create token --duration=8h`), puis teste les droits :

```text
  get pods --all-namespaces                     -> yes (attendu : yes)
  get pods --subresource=log -n demo            -> yes (attendu : yes)
  delete pods -n demo                           -> no  (attendu : no)
  patch deployments -n demo                     -> no  (attendu : no)
  create pods --subresource=exec -n demo        -> no  (attendu : no)
  get secrets -n demo                           -> no  (attendu : no)
  get secrets -n monitoring                     -> no  (attendu : no)
```

**Vérifier toi-même**

```bash
export KUBECONFIG=$PWD/kubeconfig/homelab-ai-readonly.yaml
kubectl -n demo get pods                          # marche
kubectl -n demo delete deploy hello               # Forbidden
kubectl -n monitoring get secrets                 # Forbidden
```

**Pièges**

- Les ConfigMaps sont lisibles : ne mets jamais de secret dans une ConfigMap (c'est une bonne règle de toute façon).
- Le jeton expire après 8 h : relance `make ai-readonly` le week-end suivant.
- L'IA lit les noms, les logs, les événements de ton cluster et les envoie au fournisseur du modèle. Sur un vrai cluster d'entreprise, c'est une question de conformité à poser **avant**.

## 13.2 HolmesGPT

[HolmesGPT](https://github.com/HolmesGPT/holmesgpt) est un projet *Sandbox* de la CNCF. Il interroge Kubernetes, Prometheus et d'autres sources, puis demande au modèle de raisonner sur les résultats. Version testée : 0.47.0.

**Installer** (sur ton laptop) :

```bash
brew tap robusta-dev/homebrew-holmesgpt && brew install holmesgpt
# ou
pipx install holmesgpt
holmes ask --help
```

**Piège** : HolmesGPT 0.47 exige Python **3.10 à 3.13**. Si ton Python par défaut est 3.14 : `pipx install --python python3.13 holmesgpt`. Il a aussi besoin de `kubectl` dans le `PATH`.

**Configurer**

```bash
mkdir -p ~/.holmes
cp kubernetes/ai-readonly/holmes-config.example.yaml ~/.holmes/config.yaml
```

Le fichier fixe le modèle (`anthropic/claude-sonnet-5-5` par défaut, change-le selon ton fournisseur), limite les commandes shell autorisées sans confirmation au niveau `core` (lecture `kubectl`, outils texte), refuse `kubectl get secret`, et branche le toolset Prometheus sur `http://10.10.10.13:30090`.

**Utiliser** : casse d'abord l'app (panne 2 ou 3 de l'[étape 12](12-casser-une-app.md)), puis :

```bash
export KUBECONFIG=$PWD/kubeconfig/homelab-ai-readonly.yaml
sops exec-env secrets/lab.enc.env 'holmes ask "pourquoi mon pod redémarre en boucle ?"'
```

Holmes affiche les outils qu'il appelle (`kubectl describe`, `kubectl logs --previous`, requêtes Prometheus), puis sa conclusion.

**Vérifier** : refais toi-même les deux commandes qui comptent, et compare.

```bash
kubectl -n demo describe pod <pod>     # Reason / Exit Code
kubectl -n demo logs <pod> --previous
```

Si sa conclusion ne colle pas avec ce que tu lis, c'est toi qui as raison.

**Pièges**

- Si Holmes veut lancer une commande hors de sa liste, il te demande ton accord. Réponds non à tout ce qui écrit. Et même si tu dis oui, le kubeconfig lecture seule fera échouer l'écriture. Pour refuser automatiquement : `holmes ask ... --bash-always-deny`. N'utilise jamais `--bash-always-allow` sur ton laptop.
- Le toolset `prometheus/metrics` apparaît en échec au démarrage : Prometheus n'est pas joignable. Teste `curl http://10.10.10.13:30090/-/ready`.
- Le message « no entry in litellm's cost map » s'affiche pour les modèles récents : c'est un simple avertissement de suivi des coûts. Ta vraie protection, c'est la limite de dépenses fixée vendredi.

## 13.3 Alternative : K8sGPT

[K8sGPT](https://github.com/k8sgpt-ai/k8sgpt) (v0.4.41) analyse le cluster avec des règles fixes, puis demande au modèle d'expliquer.

```bash
brew install k8sgpt
k8sgpt auth add --backend openai --model gpt-4.1     # demande la clé
export KUBECONFIG=$PWD/kubeconfig/homelab-ai-readonly.yaml
k8sgpt analyze --filter=Pod --namespace demo                  # sans IA : la liste des problèmes
k8sgpt analyze --filter=Pod --namespace demo --explain --anonymize   # avec IA, noms masqués
```

**Piège** : K8sGPT n'a pas de backend Anthropic natif dans sa liste (OpenAI, Azure OpenAI, Bedrock, Ollama, LiteLLM...). Avec une clé Anthropic, passe par un proxy LiteLLM, ou utilise HolmesGPT.

Suite : [étape 14 : une CI minimale](14-ci-github-actions.md).
