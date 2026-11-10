#!/usr/bin/env bash
# Deploy the observability stack (Prometheus, Alertmanager, cAdvisor, node-exporter,
# Loki, Tempo, OTel Collector, Grafana, Alloy) to the current minikube cluster.
# Safe to re-run: the Grafana and Alertmanager secrets are reused if they exist.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="observability"
GRAFANA_SECRET="grafana-admin"
ALERTMANAGER_SECRET="alertmanager-telegram"

for bin in kubectl openssl; do
  command -v "$bin" >/dev/null || {
    echo "ERROR: '$bin' is required but not installed" >&2
    exit 1
  }
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
  # GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 16)}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-1}"
  kubectl -n "$NAMESPACE" create secret generic "$GRAFANA_SECRET" \
    --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
  unset GRAFANA_ADMIN_PASSWORD
fi

# Alertmanager reads the Telegram bot token from this Secret. It is created here
# rather than committed so the token never enters Git. Provide TELEGRAM_BOT_TOKEN
# in the environment or write it to secrets/telegram_bot_token.
if kubectl -n "$NAMESPACE" get secret "$ALERTMANAGER_SECRET" >/dev/null 2>&1; then
  echo "==> Secret '$ALERTMANAGER_SECRET' already exists; reusing it"
else
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  if [ -z "$TELEGRAM_BOT_TOKEN" ] && [ -f secrets/telegram_bot_token ]; then
    TELEGRAM_BOT_TOKEN="$(tr -d '\r\n' <secrets/telegram_bot_token)"
  fi
  if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    TELEGRAM_BOT_TOKEN="REPLACE_WITH_TELEGRAM_BOT_TOKEN"
    echo "WARNING: TELEGRAM_BOT_TOKEN is unset and secrets/telegram_bot_token is absent."
    echo "         Alertmanager will start, but Telegram delivery will fail until the"
    echo "         secret is updated (see deploy/k8s/observability/README.md)."
  fi
  kubectl -n "$NAMESPACE" create secret generic "$ALERTMANAGER_SECRET" \
    --from-literal=telegram_bot_token="$TELEGRAM_BOT_TOKEN"
  unset TELEGRAM_BOT_TOKEN
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
for workload in prometheus alertmanager loki tempo otel-collector grafana; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$workload" --timeout=900s
done
kubectl -n "$NAMESPACE" rollout status daemonset/cadvisor --timeout=600s
kubectl -n "$NAMESPACE" rollout status daemonset/node-exporter --timeout=600s
kubectl -n "$NAMESPACE" rollout status daemonset/alloy --timeout=600s

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
echo "       echo \"${MINIKUBE_IP:-<minikube-ip>} grafana.local alertmanager.local portfolio.local\" | sudo tee -a /etc/hosts"
echo "  2. Open Grafana:  http://grafana.local"
echo "  3. Prometheus UI (optional local port-forward):"
echo "       kubectl -n $NAMESPACE port-forward svc/prometheus 9090:9090"
