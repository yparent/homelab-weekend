# Dimanche 3/6 : déployer une app, puis la casser 3 fois

Tu déploies une petite app web, puis tu provoques les trois pannes que tu verras le plus souvent en production. Une à la fois. À chaque fois : observer, comprendre, réparer.

## L'app

Une page web en Python (bibliothèque standard uniquement), montée depuis une ConfigMap dans l'image officielle `python:3.13.18-alpine3.24`. Elle :

- **exige** la variable `APP_MESSAGE` (sinon elle s'arrête avec un message `FATAL`) ;
- charge un « cache » de 48 Mio au démarrage (elle utilise ~60 Mio en tout) ;
- répond sur `/` et `/healthz` (port 8080).

Elle respecte le profil de sécurité *restricted* de Kubernetes (utilisateur non root, système de fichiers en lecture seule, aucune capacité). Le namespace `demo` l'impose.

| Fichier | Contenu |
|---|---|
| `kubernetes/demo-app/00-namespace.yaml` | namespace `demo` (Pod Security `restricted`) |
| `kubernetes/demo-app/10-configmap.yaml` | le message et le code de l'app |
| `kubernetes/demo-app/20-deployment.yaml` | **version saine** : 2 répliques, 96 Mio demandés, 128 Mio max, sondes |
| `kubernetes/demo-app/30-service.yaml` | NodePort `30080` |
| `kubernetes/demo-app/pannes/01-image-inexistante.yaml` | panne 1 |
| `kubernetes/demo-app/pannes/02-memoire-trop-basse.yaml` | panne 2 |
| `kubernetes/demo-app/pannes/03-variable-manquante.yaml` | panne 3 |

## Déployer la version saine

```bash
kubectl apply -f kubernetes/demo-app/        # ou : make demo
kubectl -n demo rollout status deploy/hello
```

**Vérifier**

```bash
kubectl -n demo get pods                     # 2/2 Running
curl http://10.10.10.13:30080                # <h1>Bonjour depuis le homelab du week-end</h1>...
```

Garde un terminal ouvert sur `kubectl -n demo get pods -w` pendant les trois pannes.

## Panne 1 : l'image n'existe pas

```bash
kubectl apply -f kubernetes/demo-app/pannes/01-image-inexistante.yaml
```

**Observer**

```bash
kubectl -n demo get pods                     # nouveau pod : ErrImagePull puis ImagePullBackOff
kubectl -n demo describe pod <nouveau-pod>   # Events : "failed to resolve reference ... not found"
```

**Comprendre** : le kubelet n'arrive pas à télécharger l'image. Il réessaie avec un délai croissant (*BackOff*). Tag mal tapé, registre privé sans identifiants, ou limite de téléchargement Docker Hub : même symptôme, lis le message exact dans `describe`.

**Remarque** : l'app répond toujours. Le déploiement progressif (*RollingUpdate*) garde les anciens pods tant que le nouveau n'est pas prêt.

**Réparer**

```bash
kubectl apply -f kubernetes/demo-app/20-deployment.yaml
kubectl -n demo rollout status deploy/hello
```

## Panne 2 : limite mémoire trop basse

```bash
kubectl apply -f kubernetes/demo-app/pannes/02-memoire-trop-basse.yaml
```

**Observer**

```bash
kubectl -n demo get pods                     # Running, puis OOMKilled, puis CrashLoopBackOff
kubectl -n demo describe pod <nouveau-pod>
#   Last State:  Terminated
#     Reason:    OOMKilled
#     Exit Code: 137
```

**Comprendre** : l'app a besoin de ~60 Mio, la limite est à 32 Mio. Le noyau tue le processus (code 137 = 128 + signal 9). Kubernetes redémarre le conteneur, il meurt encore, et Kubernetes espace les tentatives (*CrashLoopBackOff*). Les logs ne montrent souvent rien d'utile : le processus est tué net, il n'a pas le temps d'écrire une erreur. C'est `describe` qui donne la réponse.

Au bout de quelques minutes, l'alerte `HomelabPodRestartingTooOften` passe en *Firing* dans Prometheus.

**Réparer**

```bash
kubectl apply -f kubernetes/demo-app/20-deployment.yaml
```

## Panne 3 : une variable d'environnement manque

```bash
kubectl apply -f kubernetes/demo-app/pannes/03-variable-manquante.yaml
```

**Observer**

```bash
kubectl -n demo get pods                     # Error, puis CrashLoopBackOff
kubectl -n demo logs <nouveau-pod>           # FATAL: la variable d'environnement APP_MESSAGE est absente, arret.
kubectl -n demo logs <nouveau-pod> --previous   # les logs du crash précédent
```

**Comprendre** : cette fois le processus sort tout seul avec le code 1. Même état `CrashLoopBackOff` que la panne 2, cause totalement différente. La différence se lit dans `describe` (`Reason: Error`, `Exit Code: 1` contre `OOMKilled`, `137`) et dans les logs.

**Réparer**

```bash
kubectl apply -f kubernetes/demo-app/20-deployment.yaml
kubectl -n demo rollout history deploy/hello     # la cause de chaque version (annotation change-cause)
```

`kubectl -n demo rollout undo deploy/hello` marche aussi, mais le dépôt Git reste la référence : réappliquer le fichier sain garde le cluster et le code alignés.

## La méthode, à retenir

1. `kubectl get pods` : l'**état** (ImagePullBackOff, CrashLoopBackOff, Pending...).
2. `kubectl describe pod` : les **événements** et le **dernier état** (raison, code de sortie).
3. `kubectl logs` et `logs --previous` : ce que l'app a **dit** avant de mourir.

Garde-la en tête pour l'étape suivante : l'IA doit arriver aux mêmes conclusions, et c'est toi qui vérifies.

Suite : [étape 13 : l'IA en lecture seule](13-ia-lecture-seule.md).
