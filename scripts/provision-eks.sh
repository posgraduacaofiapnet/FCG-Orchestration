#!/usr/bin/env bash
# Creates (or connects to) the FCG EKS cluster and grants the GitHub Actions role
# permission to update Deployments.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-fcg-eks}"
ROLE_NAME="${ROLE_NAME:-fcg-github-actions}"
CONFIG_FILE="${ROOT_DIR}/aws/eksctl-cluster.yaml"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need aws
need kubectl

if ! command -v eksctl >/dev/null 2>&1; then
  echo ">>> Installing eksctl into ~/bin"
  mkdir -p "${HOME}/bin"
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64|aarch64) ARCH="arm64" ;;
    x86_64) ARCH="amd64" ;;
  esac
  TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${OS}_${ARCH}.tar.gz" \
    -o "${TMP}/eksctl.tar.gz"
  tar -xzf "${TMP}/eksctl.tar.gz" -C "${TMP}"
  mv "${TMP}/eksctl" "${HOME}/bin/eksctl"
  chmod +x "${HOME}/bin/eksctl"
  export PATH="${HOME}/bin:${PATH}"
  rm -rf "${TMP}"
fi

need eksctl

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo ">>> Checking for existing cluster ${CLUSTER_NAME} in ${AWS_REGION}"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "    Cluster already exists"
else
  echo ">>> Creating cluster with eksctl (this usually takes 15-20 minutes)"
  eksctl create cluster -f "$CONFIG_FILE"
fi

echo ">>> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo ">>> Granting cluster access to ${ROLE_ARN}"
# EKS access entries (API mode) — preferred over aws-auth ConfigMap.
if aws eks list-access-entries --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  if aws eks describe-access-entry \
    --cluster-name "$CLUSTER_NAME" \
    --principal-arn "$ROLE_ARN" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "    Access entry already exists"
  else
    aws eks create-access-entry \
      --cluster-name "$CLUSTER_NAME" \
      --principal-arn "$ROLE_ARN" \
      --type STANDARD \
      --region "$AWS_REGION" >/dev/null
    aws eks associate-access-policy \
      --cluster-name "$CLUSTER_NAME" \
      --principal-arn "$ROLE_ARN" \
      --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
      --access-scope type=cluster \
      --region "$AWS_REGION" >/dev/null
    echo "    Access entry created with AmazonEKSEditPolicy"
  fi
else
  echo "    Could not manage access entries; ensure ${ROLE_ARN} can edit Deployments."
fi

echo ">>> Cluster nodes"
kubectl get nodes -o wide || true

cat <<EOF

EKS ready: ${CLUSTER_NAME}
Kubeconfig updated for the current shell user.

Next:
  ./scripts/apply-k8s-secrets.sh
  kubectl apply -k k8s
  kubectl apply -f ../FCG-UsersAPI/k8s/
  kubectl apply -f ../FCG-CatalogAPI/k8s/
  kubectl apply -f ../FCG-PaymentsAPI/k8s/
  kubectl apply -f k8s/gateway/
EOF
