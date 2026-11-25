#!/usr/bin/env bash
# Builds a READ-ONLY kubeconfig for the AI tools, with a short-lived token.
# Run from the repo root, after: kubectl apply -f kubernetes/ai-readonly/rbac.yaml
#
#   bash kubernetes/ai-readonly/make-readonly-kubeconfig.sh
#   export KUBECONFIG=$PWD/kubeconfig/homelab-ai-readonly.yaml
#
# The token expires after DURATION (default 8h): run the script again next time.
set -euo pipefail

ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-kubeconfig/homelab.yaml}"
OUT="${OUT:-kubeconfig/homelab-ai-readonly.yaml}"
DURATION="${DURATION:-8h}"
NAMESPACE="ai-readonly"
SERVICE_ACCOUNT="ai-readonly"

[[ -f "${ADMIN_KUBECONFIG}" ]] || { echo "kubeconfig admin introuvable : ${ADMIN_KUBECONFIG}" >&2; exit 1; }

server=$(kubectl --kubeconfig "${ADMIN_KUBECONFIG}" config view --minify --raw \
  -o jsonpath='{.clusters[0].cluster.server}')
ca_data=$(kubectl --kubeconfig "${ADMIN_KUBECONFIG}" config view --minify --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
token=$(kubectl --kubeconfig "${ADMIN_KUBECONFIG}" -n "${NAMESPACE}" \
  create token "${SERVICE_ACCOUNT}" --duration="${DURATION}")

mkdir -p "$(dirname "${OUT}")"
umask 077
cat > "${OUT}" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: homelab
    cluster:
      server: ${server}
      certificate-authority-data: ${ca_data}
users:
  - name: ai-readonly
    user:
      token: ${token}
contexts:
  - name: homelab-ai-readonly
    context:
      cluster: homelab
      user: ai-readonly
      namespace: demo
current-context: homelab-ai-readonly
KUBECONFIG

echo "Kubeconfig lecture seule ecrit : ${OUT} (valable ${DURATION})"
echo
echo "Verification (le serveur API repond, pas l'IA) :"
check() {
  local expected="$1"; shift
  local got
  got=$(kubectl --kubeconfig "${OUT}" auth can-i "$@" 2>/dev/null || true)
  printf '  %-45s -> %-3s (attendu : %s)\n' "$*" "${got}" "${expected}"
}
check yes get pods --all-namespaces
check yes get pods --subresource=log -n demo
check no  delete pods -n demo
check no  patch deployments -n demo
check no  create pods --subresource=exec -n demo
check no  get secrets -n demo
check no  get secrets -n monitoring
