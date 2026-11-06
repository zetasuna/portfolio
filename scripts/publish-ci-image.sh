#!/usr/bin/env bash
# Build and publish the CI agent image used by Jenkins (label: docker-go).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGE="${CI_IMAGE:-nam2107/portfolio-ci}"
TAG="${CI_IMAGE_TAG:-1.0.0}"

docker build -f deploy/ci/Dockerfile -t "${IMAGE}:${TAG}" .
docker tag "${IMAGE}:${TAG}" "${IMAGE}:latest"
docker push "${IMAGE}:${TAG}"
docker push "${IMAGE}:latest"
echo "Published ${IMAGE}:${TAG} and ${IMAGE}:latest"
