#!/usr/bin/env bash
# Applies Kubernetes Secrets from local files that are NOT committed.
# Copies *.example.yaml -> secret files on first run, then kubectl apply.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(cd "${ROOT_DIR}/.." && pwd)"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need kubectl

ensure_from_example() {
  local target="$1"
  local example="$2"
  if [[ ! -f "$target" ]]; then
    if [[ ! -f "$example" ]]; then
      echo "Missing example secret: $example" >&2
      exit 1
    fi
    cp "$example" "$target"
    echo "Created ${target} from example — edit real values before production use."
  fi
}

ensure_from_example \
  "${ROOT_DIR}/k8s/sqlserver-secrets.yaml" \
  "${ROOT_DIR}/k8s/sqlserver-secrets.example.yaml"
ensure_from_example \
  "${ROOT_DIR}/k8s/gateway/kong-secret.yaml" \
  "${ROOT_DIR}/k8s/gateway/kong-secret.example.yaml"
ensure_from_example \
  "${PARENT}/FCG-UsersAPI/k8s/secret.yaml" \
  "${PARENT}/FCG-UsersAPI/k8s/secret.example.yaml"
ensure_from_example \
  "${PARENT}/FCG-CatalogAPI/k8s/secret.yaml" \
  "${PARENT}/FCG-CatalogAPI/k8s/secret.example.yaml"
ensure_from_example \
  "${PARENT}/FCG-PaymentsAPI/k8s/secret.yaml" \
  "${PARENT}/FCG-PaymentsAPI/k8s/secret.example.yaml"

echo ">>> Applying secrets"
kubectl apply -f "${ROOT_DIR}/k8s/sqlserver-secrets.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/gateway/kong-secret.yaml"
kubectl apply -f "${PARENT}/FCG-UsersAPI/k8s/secret.yaml"
kubectl apply -f "${PARENT}/FCG-CatalogAPI/k8s/secret.yaml"
kubectl apply -f "${PARENT}/FCG-PaymentsAPI/k8s/secret.yaml"
echo ">>> Secrets applied"
