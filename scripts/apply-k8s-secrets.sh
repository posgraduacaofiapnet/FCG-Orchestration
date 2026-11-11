#!/usr/bin/env bash
# Applies Kubernetes Secrets from local files that are NOT committed.
# Copies *.example.yaml -> secret files on first run, then kubectl apply.
# Refuses to apply placeholders (REPLACE_ME / REPLACE_WITH_*).
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
    echo "Created ${target} from example — edit real values before re-running."
  fi
}

assert_no_placeholders() {
  local file="$1"
  if grep -Eq 'REPLACE_ME|REPLACE_WITH_' "$file"; then
    echo "Refusing to apply ${file}: still contains REPLACE_* placeholders." >&2
    echo "Edit the file with real credentials, then run this script again." >&2
    exit 1
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

SECRET_FILES=(
  "${ROOT_DIR}/k8s/sqlserver-secrets.yaml"
  "${ROOT_DIR}/k8s/gateway/kong-secret.yaml"
  "${PARENT}/FCG-UsersAPI/k8s/secret.yaml"
  "${PARENT}/FCG-CatalogAPI/k8s/secret.yaml"
  "${PARENT}/FCG-PaymentsAPI/k8s/secret.yaml"
)

for file in "${SECRET_FILES[@]}"; do
  assert_no_placeholders "$file"
done

echo ">>> Applying secrets"
for file in "${SECRET_FILES[@]}"; do
  kubectl apply -f "$file"
done
echo ">>> Secrets applied"
