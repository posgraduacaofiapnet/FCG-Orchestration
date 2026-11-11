#!/usr/bin/env bash
# Applies API ConfigMaps, Services, and Deployments only.
# Never applies secret.example.yaml (would overwrite live credentials).
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

apply_api() {
  local api_dir="$1"
  local name
  name="$(basename "$api_dir")"
  echo ">>> ${name}"
  kubectl apply -f "${api_dir}/k8s/configmap.yaml"
  kubectl apply -f "${api_dir}/k8s/service.yaml"
  kubectl apply -f "${api_dir}/k8s/deployment.yaml"
}

apply_api "${PARENT}/FCG-UsersAPI"
apply_api "${PARENT}/FCG-CatalogAPI"
apply_api "${PARENT}/FCG-PaymentsAPI"

echo ">>> API manifests applied (secrets unchanged)"
