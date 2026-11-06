# syntax=docker/dockerfile:1.7
#
# CI agent for the GitHub -> Jenkins -> Docker Hub -> Argo CD pipeline.
# Build and publish with:
#   ./scripts/publish-ci-image.sh
#
# Based on the Jenkins inbound agent so the Docker plugin can launch it as a
# node. Register a Docker Cloud agent template with label "docker-go".
FROM docker:28.5.2-cli AS dockercli
FROM aquasec/trivy:0.69.0 AS trivy

FROM jenkins/inbound-agent:latest-jdk21

ARG GO_VERSION=1.27.2
ARG KUSTOMIZE_VERSION=v5.7.1
ARG ARGOCD_VERSION=v3.6.1
ARG GOTESTSUM_VERSION=v1.13.0

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    DOCKER_HOST=unix:///var/run/docker.sock \
    PATH=/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash build-essential ca-certificates curl git jq openssl unzip \
  && rm -rf /var/lib/apt/lists/*

# Go is needed for build/test/govulncheck; the inbound agent image has no Go.
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" \
    | tar -xz -C /usr/local; \
  go version

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) kustomize_arch=amd64; argocd_arch=amd64 ;; \
    arm64) kustomize_arch=arm64; argocd_arch=arm64 ;; \
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${kustomize_arch}.tar.gz" \
    | tar -xz -C /usr/local/bin kustomize; \
  curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${argocd_arch}"; \
  chmod +x /usr/local/bin/argocd; \
  GOBIN=/usr/local/bin go install "gotest.tools/gotestsum@${GOTESTSUM_VERSION}"

# The Docker agent template starts the container as root (needed for the
# mounted docker.sock). Keep the inbound-agent workdir.
WORKDIR /home/jenkins/agent
