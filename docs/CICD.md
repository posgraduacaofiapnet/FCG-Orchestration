# FCG CI/CD (Phase 4) — GitHub Actions + AWS EKS/ECR

## Pipeline

On every push to `master` in `FCG-UsersAPI`, `FCG-CatalogAPI`, and `FCG-PaymentsAPI`:

1. Build & unit tests
2. Build Docker image tagged with the git SHA
3. Trivy vulnerability scan (non-blocking)
4. Push to Amazon ECR (private registry)
5. Rolling update on Amazon EKS (`maxUnavailable: 0`)

Pull requests only run tests.

Authentication uses **GitHub OIDC → IAM role** (no long-lived AWS keys in GitHub).

## One-time setup

Prerequisites on your machine:

- AWS credentials (`aws configure` or SSO)
- `gh auth login` with access to `posgraduacaofiapnet/*`
- `aws`, `kubectl`, `jq`, `gh`

```bash
cd FCG-Orchestration
export AWS_REGION=us-east-1
export CLUSTER_NAME=fcg-eks

./scripts/provision-cicd.sh   # ECR + OIDC IAM role + GitHub secrets
./scripts/provision-eks.sh    # create/reuse EKS and grant deploy role
./scripts/apply-k8s-secrets.sh
kubectl apply -k k8s
kubectl apply -f k8s/gateway/
kubectl apply -f ../FCG-UsersAPI/k8s/
kubectl apply -f ../FCG-CatalogAPI/k8s/
kubectl apply -f ../FCG-PaymentsAPI/k8s/
```

GitHub repository secrets (environment `production`):

| Secret / Var | Purpose |
|---|---|
| `AWS_ROLE_ARN` | IAM role assumed by Actions via OIDC |
| `EKS_CLUSTER_NAME` | Target cluster name |
| `AWS_REGION` (variable) | Defaults to `us-east-1` |

## Secrets policy

Connection strings, JWT keys, and DB passwords must **not** live in git.

- Committed: `k8s/secret.example.yaml`
- Local only (gitignored): `k8s/secret.yaml`
- Applied with `./scripts/apply-k8s-secrets.sh`

## Cost note

EKS control plane + 2× `t3.medium` nodes incur ongoing AWS charges. Delete the cluster when the challenge is graded if this is a personal account:

```bash
eksctl delete cluster -f aws/eksctl-cluster.yaml
```
