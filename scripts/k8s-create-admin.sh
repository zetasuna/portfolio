#!/usr/bin/env bash
# Bootstrap the first admin account in the minikube deployment.
# Credentials are placed in a temporary Kubernetes Secret and removed afterwards.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="${NAMESPACE:-portfolio}"
ADMIN_SECRET="portfolio-admin"
JOB="create-admin"

command -v kubectl >/dev/null || { echo "ERROR: 'kubectl' is required" >&2; exit 1; }

read -r -p 'Admin username (3-80 characters): ' ADMIN_USERNAME
read -r -s -p 'Admin password (at least 12 characters): ' ADMIN_PASSWORD
echo
read -r -s -p 'Repeat password: ' ADMIN_PASSWORD_CONFIRM
echo

[[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]] || { echo 'ERROR: passwords did not match' >&2; exit 1; }
[[ ${#ADMIN_PASSWORD} -ge 12 ]] || { echo 'ERROR: password must be at least 12 characters' >&2; exit 1; }
[[ ${#ADMIN_USERNAME} -ge 3 && ${#ADMIN_USERNAME} -le 80 ]] || { echo 'ERROR: username must be 3-80 characters' >&2; exit 1; }

cleanup() {
  kubectl -n "$NAMESPACE" delete secret "$ADMIN_SECRET" --ignore-not-found >/dev/null 2>&1 || true
  unset ADMIN_PASSWORD ADMIN_PASSWORD_CONFIRM
}
trap cleanup EXIT

kubectl -n "$NAMESPACE" delete job "$JOB" --ignore-not-found >/dev/null
kubectl -n "$NAMESPACE" create secret generic "$ADMIN_SECRET" \
  --from-literal=ADMIN_USERNAME="$ADMIN_USERNAME" \
  --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD"

echo "==> Running $JOB job"
kubectl -n "$NAMESPACE" apply -f deploy/k8s/jobs/create-admin-job.yaml

if ! kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$JOB" --timeout=180s; then
  echo "ERROR: admin bootstrap failed; logs:" >&2
  kubectl -n "$NAMESPACE" logs "job/$JOB" --all-containers=true >&2 || true
  exit 1
fi

echo "==> Job logs"
kubectl -n "$NAMESPACE" logs "job/$JOB" --all-containers=true

kubectl -n "$NAMESPACE" delete job "$JOB" --ignore-not-found >/dev/null
echo "==> Admin account '$ADMIN_USERNAME' is ready. Sign in at http://portfolio.local/admin/login"
