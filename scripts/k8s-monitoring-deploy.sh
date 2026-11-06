#!/usr/bin/env bash
# Deploy the observability stack (Prometheus, cAdvisor, Loki, Tempo, OTel Collector,
# Grafana, Alloy) to the current minikube cluster.
# Safe to re-run: the Grafana admin secret is reused if it already exists.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="observability"
GRAFANA_SECRET="grafana-admin"

for bin in kubectl openssl; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' is required but not installed" >&2; exit 1; }
done

echo "==> Creating namespace '$NAMESPACE'"
kubectl apply -f deploy/k8s/observability/namespace.yaml

# The Grafana Ingress needs the minikube ingress controller.
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  echo "==> Enabling the minikube ingress addon"
  minikube addons enable ingress
fi
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

if kubectl -n "$NAMESPACE" get secret "$GRAFANA_SECRET" >/dev/null 2>&1; then
  echo "==> Secret '$GRAFANA_SECRET' already exists; reusing it"
else
  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 16)}"
  kubectl -n "$NAMESPACE" create secret generic "$GRAFANA_SECRET" \
    --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
  unset GRAFANA_ADMIN_PASSWORD
fi

echo "==> Applying observability manifests"
kubectl apply -k deploy/k8s/observability

# Point the app at the collector and allow Prometheus to scrape its Service name.
if kubectl get namespace portfolio >/dev/null 2>&1; then
  echo "==> Updating the portfolio app (OTLP endpoint + scrape host allowlist)"
  kubectl apply -k deploy/k8s
  kubectl -n portfolio rollout restart deployment/portfolio
  kubectl -n portfolio rollout status deployment/portfolio --timeout=300s
fi

echo "==> Waiting for workloads"
for workload in prometheus loki tempo otel-collector grafana; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$workload" --timeout=900s
done
kubectl -n "$NAMESPACE" rollout status daemonset/cadvisor --timeout=300s
kubectl -n "$NAMESPACE" rollout status daemonset/alloy --timeout=300s

MINIKUBE_IP="$(minikube ip 2>/dev/null || true)"

echo
echo "==> Pods"
kubectl -n "$NAMESPACE" get pods -o wide
echo
echo "==> Services / ingress"
kubectl -n "$NAMESPACE" get svc,ingress
echo
echo "Grafana admin credentials:"
echo "  user:     $(kubectl -n "$NAMESPACE" get secret "$GRAFANA_SECRET" -o jsonpath='{.data.admin-user}' | base64 -d)"
echo "  password: $(kubectl -n "$NAMESPACE" get secret "$GRAFANA_SECRET" -o jsonpath='{.data.admin-password}' | base64 -d)"
echo
echo "Next steps:"
echo "  1. Add the host entry (once), if not already present:"
echo "       echo \"${MINIKUBE_IP:-<minikube-ip>} grafana.local portfolio.local\" | sudo tee -a /etc/hosts"
echo "  2. Open Grafana:  http://grafana.local"
echo "  3. Prometheus UI (optional local port-forward):"
echo "       kubectl -n $NAMESPACE port-forward svc/prometheus 9090:9090"
