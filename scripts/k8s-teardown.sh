#!/usr/bin/env bash
# Remove the portfolio deployment from the cluster. THIS DELETES THE DATABASE AND UPLOADS.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="${NAMESPACE:-portfolio}"

echo "WARNING: this deletes namespace '$NAMESPACE', including the PostgreSQL volume and uploaded files."
read -r -p "Type '$NAMESPACE' to confirm: " CONFIRM
[[ "$CONFIRM" == "$NAMESPACE" ]] || { echo "Aborted."; exit 1; }

kubectl delete namespace "$NAMESPACE" --ignore-not-found

if [[ "${1:-}" == "--disable-ingress" ]]; then
  minikube addons disable ingress
  echo "Reminder: remove the 'portfolio.local' line from /etc/hosts manually."
fi
