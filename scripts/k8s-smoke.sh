#!/usr/bin/env bash
# Smoke test the minikube deployment through the ingress controller.
#
# Jenkins runs this from a container, so it addresses the ingress by IP and
# sets the Host header explicitly instead of relying on /etc/hosts.
set -euo pipefail

BASE_URL="${BASE_URL:-http://${SMOKE_HOST:-192.168.49.2}}"
HOST_HEADER="${HOST_HEADER:-portfolio.local}"
CURL="${CURL:-curl}"

request() {
  local path="$1" expected="${2:-200}"
  local code
  code="$("$CURL" --silent --show-error --max-time 10 \
    -H "Host: $HOST_HEADER" \
    --output /dev/null --write-out '%{http_code}' \
    "${BASE_URL}${path}")"
  if [[ "$code" != "$expected" ]]; then
    printf 'FAIL %s -> %s (expected %s)\n' "$path" "$code" "$expected" >&2
    return 1
  fi
  printf 'PASS %s -> %s\n' "$path" "$code"
}

request /healthz
request /readyz
request /projects
request /

echo "PASS application smoke test ($BASE_URL, Host: $HOST_HEADER)"
