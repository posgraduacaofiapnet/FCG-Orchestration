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
- `aws`, `kubectl`, `gh`

```bash
cd FCG-Orchestration
export AWS_REGION=us-east-1
export CLUSTER_NAME=fcg-eks

./scripts/provision-cicd.sh   # ECR + OIDC IAM role + GitHub secrets
./scripts/provision-eks.sh    # create/reuse EKS and grant deploy role

# Edit the generated local secret files (gitignored), then:
./scripts/apply-k8s-secrets.sh

# Infra only (secrets are NOT in this kustomization)
kubectl apply -k k8s
kubectl apply -f k8s/gateway/kong-config.yaml
kubectl apply -f k8s/gateway/kong-deployment.yaml
kubectl apply -f k8s/gateway/kong-service.yaml

# APIs — never apply *.example.yaml (it would overwrite live secrets)
./scripts/apply-api-manifests.sh
```

GitHub **repository** secrets / variables (not Environments):

| Secret / Var | Purpose |
|---|---|
| `AWS_ROLE_ARN` | IAM role assumed by Actions via OIDC |
| `EKS_CLUSTER_NAME` | Target cluster name (`fcg-eks`) |
| `AWS_REGION` (variable) | Defaults to `us-east-1` |

## Secrets policy

Connection strings, JWT keys, and DB passwords must **not** live in git.

- Committed: `k8s/secret.example.yaml` / `*-secrets.example.yaml`
- Local only (gitignored): `k8s/secret.yaml`, `sqlserver-secrets.yaml`, `kong-secret.yaml`
- Applied with `./scripts/apply-k8s-secrets.sh` (refuses placeholders like `REPLACE_ME`)

Do **not** run `kubectl apply -f ../FCG-*/k8s/` — that would include `secret.example.yaml` and can wipe real credentials.

## Cost note

EKS control plane (~$0.10/hour) plus worker nodes and the Kong Load Balancer incur ongoing charges. Nodes in `aws/eksctl-cluster.yaml` use Free Tier–eligible `m7i-flex.large`. Delete the cluster when the challenge is graded:

```bash
eksctl delete cluster --name fcg-eks --region us-east-1
```
