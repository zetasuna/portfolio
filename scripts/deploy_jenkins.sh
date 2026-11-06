#!/usr/bin/env bash
# Start (or rebuild) the Jenkins controller and its permanent CI agent.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f .env ]] || {
  echo "Missing .env. Run ./scripts/setup.sh first." >&2
  exit 1
}

PROJECT_DIR="$(pwd -P)"

docker compose \
  --env-file "${PROJECT_DIR}/.env" \
  --profile ci \
  -f "${PROJECT_DIR}/compose.yaml" \
  up -d --build jenkins jenkins-agent
docker compose --env-file "${PROJECT_DIR}/.env" --profile ci ps jenkins jenkins-agent
