#!/usr/bin/env bash
# Install Argo CD and register the portfolio Applications.
#
# This is a one-time bootstrap. After it completes, Argo CD owns the
# 'portfolio' and 'observability' namespaces; do not run kubectl apply -k on
# them manually.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAMESPACE="argocd"
BRANCH="${GITOPS_BRANCH:-deploy}"

for bin in kubectl git; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' is required" >&2; exit 1; }
done

CONTEXT="$(kubectl config current-context)"
if [[ "$CONTEXT" != "minikube" ]]; then
  echo "WARNING: current context is '$CONTEXT', expected 'minikube'." >&2
  read -r -p "Continue anyway? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

if ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "WARNING: working tree has uncommitted/untracked changes; they will NOT be in the '$BRANCH' branch." >&2
  fi
  echo "==> GitOps branch '$BRANCH' does not exist; creating it from HEAD"
  git push origin "HEAD:${BRANCH}"
fi

echo "==> Installing Argo CD"
# Server-side apply avoids the 256 KiB last-applied annotation limit on the
# large Argo CD CRD schemas.
kubectl apply --server-side -k deploy/argocd
kubectl -n "$NAMESPACE" rollout status deployment/argocd-server --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n "$NAMESPACE" rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Registering Applications"
kubectl apply -k deploy/argocd/apps

echo
echo "==> Argo CD is ready"
echo "  UI (after /etc/hosts entry): http://argocd.local"
echo "  Initial admin password:"
echo "    kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo
echo "First sync is intentionally reviewed before auto-sync settles:"
echo "  argocd app diff portfolio-app"
echo "  argocd app diff portfolio-observability"
echo
echo "Add the host entry once:"
echo "  echo \"\$(minikube ip) argocd.local\" | sudo tee -a /etc/hosts"
