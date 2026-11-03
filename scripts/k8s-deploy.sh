#!/usr/bin/env bash
# Deploy the portfolio app and PostgreSQL to the current (minikube) cluster.
# Safe to re-run: the database secret is reused if it already exists.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="${NAMESPACE:-portfolio}"
DB_SECRET="${DB_SECRET:-portfolio-db}"
POSTGRES_DB="${POSTGRES_DB:-portfolio}"
POSTGRES_USER="${POSTGRES_USER:-portfolio_admin}"
APP_DB_USER="${APP_DB_USER:-portfolio_app}"

for bin in kubectl minikube openssl; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' is required but not installed" >&2; exit 1; }
done

echo "==> Enabling the minikube ingress addon (no-op if already enabled)"
minikube addons enable ingress

echo "==> Waiting for the ingress controller"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

echo "==> Creating namespace '$NAMESPACE'"
kubectl apply -f deploy/k8s/namespace.yaml

if kubectl -n "$NAMESPACE" get secret "$DB_SECRET" >/dev/null 2>&1; then
  echo "==> Secret '$DB_SECRET' already exists; reusing it"
else
  echo "==> Generating database secret '$DB_SECRET'"
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  APP_DB_PASSWORD="$(openssl rand -hex 24)"
  # Hex passwords keep the URL safe without percent-encoding.
  DATABASE_URL="postgres://${APP_DB_USER}:${APP_DB_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
  kubectl -n "$NAMESPACE" create secret generic "$DB_SECRET" \
    --from-literal=POSTGRES_DB="$POSTGRES_DB" \
    --from-literal=POSTGRES_USER="$POSTGRES_USER" \
    --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    --from-literal=APP_DB_USER="$APP_DB_USER" \
    --from-literal=APP_DB_PASSWORD="$APP_DB_PASSWORD" \
    --from-literal=DATABASE_URL="$DATABASE_URL"
  unset POSTGRES_PASSWORD APP_DB_PASSWORD DATABASE_URL
fi

echo "==> Applying manifests"
kubectl apply -k deploy/k8s

echo "==> Waiting for PostgreSQL"
kubectl -n "$NAMESPACE" rollout status statefulset/postgres --timeout=300s

echo "==> Waiting for the application"
kubectl -n "$NAMESPACE" rollout status deployment/portfolio --timeout=300s

echo
echo "==> Pods"
kubectl -n "$NAMESPACE" get pods -o wide
echo
echo "==> Services / ingress"
kubectl -n "$NAMESPACE" get svc,ingress
echo
MINIKUBE_IP="$(minikube ip)"
echo "Next steps:"
echo "  1. Add the host entry (once):"
echo "       echo \"$MINIKUBE_IP portfolio.local\" | sudo tee -a /etc/hosts"
echo "  2. Check health:"
echo "       curl -i http://portfolio.local/healthz"
echo "       curl -i http://portfolio.local/readyz"
echo "       curl -i http://portfolio.local/projects"
echo "  3. Create the first admin:"
echo "       ./scripts/k8s-create-admin.sh"
