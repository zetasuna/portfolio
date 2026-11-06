#!/usr/bin/env bash
# Remove workloads from the minikube cluster.
#
#   ./scripts/k8s-teardown.sh              # app only (portfolio namespace)
#   ./scripts/k8s-teardown.sh monitoring   # observability only
#   ./scripts/k8s-teardown.sh all          # both
#
# Add --disable-ingress to also disable the minikube ingress addon.
# THIS DELETES DATABASE/UPLOAD DATA (app) AND METRICS/LOGS/TRACES (monitoring).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

MODE="${1:-app}"
DISABLE_INGRESS=false
for arg in "$@"; do
  [[ "$arg" == "--disable-ingress" ]] && DISABLE_INGRESS=true
done
case "$MODE" in
  app | monitoring | all) ;;
  --disable-ingress) MODE="app" ;;
  *)
    echo "usage: $0 [app|monitoring|all] [--disable-ingress]" >&2
    exit 2
    ;;
esac

echo "WARNING: this deletes the following from the cluster:"
[[ "$MODE" == "app" || "$MODE" == "all" ]] && echo "  - namespace 'portfolio' (PostgreSQL volume and uploaded files included)"
[[ "$MODE" == "monitoring" || "$MODE" == "all" ]] && echo "  - namespace 'observability' (Prometheus/Loki/Tempo/Grafana volumes included)"
echo "  - cluster-scoped RBAC for Grafana Alloy (monitoring only)"
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

if [[ "$MODE" == "app" || "$MODE" == "all" ]]; then
  kubectl delete namespace portfolio --ignore-not-found
fi

if [[ "$MODE" == "monitoring" || "$MODE" == "all" ]]; then
  kubectl delete namespace observability --ignore-not-found
  kubectl delete clusterrolebinding portfolio-alloy-logs --ignore-not-found
  kubectl delete clusterrole portfolio-alloy-logs --ignore-not-found
fi

if [[ "$DISABLE_INGRESS" == "true" ]]; then
  minikube addons disable ingress
  echo "Reminder: remove the grafana.local / portfolio.local lines from /etc/hosts manually."
fi
