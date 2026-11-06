#!/usr/bin/env bash
# Copy the current manifests to the GitOps branch and pin the new image tag.
#
# Jenkins runs this on main after pushing the image. Argo CD watches
# GITOPS_BRANCH, so the tag bump reaches the cluster without Jenkins ever
# talking to Kubernetes.
#
# Usage: GITOPS_PUSH_URL=... ./scripts/ci-gitops-bump.sh <tag>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TAG="${1:-}"
[[ -n "$TAG" ]] || { echo "usage: $0 <image-tag>" >&2; exit 2; }

BRANCH="${GITOPS_BRANCH:-deploy}"
REMOTE="${GITOPS_REMOTE:-origin}"
REPO_URL="${GITOPS_REPO_URL:-$(git remote get-url "$REMOTE")}"
PUSH_URL="${GITOPS_PUSH_URL:-$REPO_URL}"
IMAGE="${GITOPS_IMAGE:-nam2107/portfolio}"

if [[ -n "${GITHUB_TOKEN:-}" && -z "${GITOPS_PUSH_URL:-}" && "$REPO_URL" == https://github.com/* ]]; then
  PUSH_URL="${REPO_URL/https:\/\/github.com\//https:\/\/x-access-token:${GITHUB_TOKEN}@github.com\/}"
fi

git config user.name "${GITOPS_GIT_NAME:-portfolio-ci}"
git config user.email "${GITOPS_GIT_EMAIL:-portfolio-ci@users.noreply.github.com}"

TMP="$(mktemp -d)"
cleanup() {
  git worktree remove --force "$TMP" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

git fetch --no-tags "$REMOTE" main >/dev/null 2>&1 || true

if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
  git fetch --no-tags "$REMOTE" "$BRANCH"
  git worktree add --force -B "$BRANCH" "$TMP" "$REMOTE/$BRANCH" >/dev/null
else
  echo "==> Creating GitOps branch '$BRANCH' from the current checkout"
  git worktree add --force -B "$BRANCH" "$TMP" HEAD >/dev/null
fi

# Mirror the manifests from the build commit. The GitOps branch only differs by
# the image tag, so it can never drift from main.
rm -rf "$TMP/deploy"
cp -a deploy "$TMP/deploy"

(
  cd "$TMP"
  (cd deploy/k8s && kustomize edit set image "${IMAGE}=${IMAGE}:${TAG}")
  git add -A deploy/k8s/kustomization.yaml
  if git diff --cached --quiet; then
    echo "==> GitOps branch already pins $IMAGE:$TAG"
    exit 0
  fi
  git commit -m "chore(gitops): ${IMAGE}:${TAG}"
  git push "$PUSH_URL" "HEAD:${BRANCH}"
  echo "==> Pushed $IMAGE:$TAG to branch '$BRANCH'"
)
