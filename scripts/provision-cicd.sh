#!/usr/bin/env bash
# Creates ECR repositories, GitHub OIDC trust in IAM, and GitHub Actions secrets/vars
# for FCG-UsersAPI, FCG-CatalogAPI, FCG-PaymentsAPI (and optionally Orchestration).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-fcg-eks}"
ROLE_NAME="${ROLE_NAME:-fcg-github-actions}"
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
GITHUB_ORG="${GITHUB_ORG:-posgraduacaofiapnet}"
REPOS=(
  "FCG-UsersAPI"
  "FCG-CatalogAPI"
  "FCG-PaymentsAPI"
)
ECR_REPOS=(
  "fcg-users-api"
  "fcg-catalog-api"
  "fcg-payments-api"
)

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need aws
need gh
need python3

echo ">>> Checking AWS identity"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "    Account: ${ACCOUNT_ID}"
echo "    Region:  ${AWS_REGION}"

echo ">>> Checking GitHub auth"
gh auth status

echo ">>> Creating ECR repositories"
for repo in "${ECR_REPOS[@]}"; do
  if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "    ECR exists: $repo"
  else
    aws ecr create-repository \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 >/dev/null
    echo "    ECR created: $repo"
  fi
done

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
echo ">>> Ensuring GitHub OIDC provider"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "    OIDC provider already exists"
else
  THUMBPRINT="$(python3 - <<'PY'
import ssl, socket, hashlib
hostname = "token.actions.githubusercontent.com"
ctx = ssl.create_default_context()
with socket.create_connection((hostname, 443), timeout=10) as sock:
    with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
        der = ssock.getpeercert(binary_form=True)
print(hashlib.sha1(der).hexdigest())
PY
)"
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_PROVIDER_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$THUMBPRINT" >/dev/null
  echo "    OIDC provider created"
fi

# Match master pushes and workflow_dispatch (no GitHub Environment required).
REPO_SUBJECTS=()
for repo in "${REPOS[@]}"; do
  REPO_SUBJECTS+=("repo:${GITHUB_ORG}/${repo}:ref:refs/heads/master")
  REPO_SUBJECTS+=("repo:${GITHUB_ORG}/${repo}:*")
done

# Build trust policy JSON
TRUST_FILE="$(mktemp)"
POLICY_FILE="$(mktemp)"
trap 'rm -f "$TRUST_FILE" "$POLICY_FILE"' EXIT

{
  echo '{'
  echo '  "Version": "2012-10-17",'
  echo '  "Statement": ['
  echo '    {'
  echo '      "Effect": "Allow",'
  echo '      "Principal": { "Federated": "'"$OIDC_ARN"'" },'
  echo '      "Action": "sts:AssumeRoleWithWebIdentity",'
  echo '      "Condition": {'
  echo '        "StringEquals": { "'"$OIDC_PROVIDER_URL"':aud": "sts.amazonaws.com" },'
  echo '        "StringLike": { "'"$OIDC_PROVIDER_URL"':sub": ['
  for i in "${!REPO_SUBJECTS[@]}"; do
    sep=","
    if [[ "$i" -eq $((${#REPO_SUBJECTS[@]} - 1)) ]]; then sep=""; fi
    echo "          \"${REPO_SUBJECTS[$i]}\"${sep}"
  done
  echo '        ] }'
  echo '      }'
  echo '    }'
  echo '  ]'
  echo '}'
} >"$TRUST_FILE"

cat >"$POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrAuth",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Sid": "EcrPushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ],
      "Resource": [
        "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/fcg-users-api",
        "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/fcg-catalog-api",
        "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/fcg-payments-api"
      ]
    },
    {
      "Sid": "EksDescribe",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
EOF

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ">>> Ensuring IAM role ${ROLE_NAME}"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "file://${TRUST_FILE}"
  echo "    Trust policy updated"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${TRUST_FILE}" \
    --description "GitHub Actions deploy role for FCG CI/CD" >/dev/null
  echo "    Role created"
fi

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "fcg-github-actions-inline" \
  --policy-document "file://${POLICY_FILE}" >/dev/null
echo "    Inline policy attached"

echo ">>> Configuring GitHub repository secrets / vars"
for repo in "${REPOS[@]}"; do
  full="${GITHUB_ORG}/${repo}"
  echo "    ${full}"
  # Repo-level secrets work with write access; Environments require admin.
  gh variable set AWS_REGION --repo "$full" --body "$AWS_REGION"
  gh secret set AWS_ROLE_ARN --repo "$full" --body "$ROLE_ARN"
  gh secret set EKS_CLUSTER_NAME --repo "$full" --body "$CLUSTER_NAME"
done

# Patch ACCOUNT_ID placeholders in sibling API deployment manifests (local working copies).
PARENT="$(cd "${ROOT_DIR}/.." && pwd)"
for api in FCG-UsersAPI FCG-CatalogAPI FCG-PaymentsAPI; do
  deploy="${PARENT}/${api}/k8s/deployment.yaml"
  if [[ -f "$deploy" ]]; then
    sed -i.bak "s/ACCOUNT_ID\\.dkr\\.ecr\\.[a-z0-9-]*\\.amazonaws\\.com/${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/g" "$deploy"
    rm -f "${deploy}.bak"
    echo "    Patched image registry in ${api}/k8s/deployment.yaml"
  fi
done

cat <<EOF

Done.

AWS_ACCOUNT_ID=${ACCOUNT_ID}
AWS_REGION=${AWS_REGION}
AWS_ROLE_ARN=${ROLE_ARN}
EKS_CLUSTER_NAME=${CLUSTER_NAME}

Next:
  1) Create/reuse the EKS cluster:  ./scripts/provision-eks.sh
  2) Edit local secret files, then: ./scripts/apply-k8s-secrets.sh
  3) Apply infra + APIs (see docs/CICD.md) — never apply *.example.yaml
  4) Merge CI PRs / push master to trigger deploy
EOF
