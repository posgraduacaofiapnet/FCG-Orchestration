# FCG CI/CD (Phase 4) — GitHub Actions + AWS EKS/ECR

## Pipeline

Revisão documental: 16/11/2026, por leitura dos workflows e scripts da `master`. Os registros de
execução de 11/11/2026 estão em [VALIDACAO.md](VALIDACAO.md); não foram repetidos nesta revisão.

On every push to `master` in `FCG-UsersAPI`, `FCG-CatalogAPI`, and `FCG-PaymentsAPI`:

1. Build & unit tests
2. Build Docker image tagged with the git SHA
3. Push to Amazon ECR (private registry), with SHA and `latest` tags
4. Trivy vulnerability scan of the published SHA image (non-blocking)
5. Update the existing Deployment image to the SHA tag and wait for the EKS rollout

Pull requests only run tests.

The same publish/deploy job runs on `workflow_dispatch`; OIDC trust and permissions must allow
the selected ref. The scan runs after push and does not prevent deployment on findings. The
manifests configure two replicas and `maxUnavailable: 0`; those settings do not by themselves
prove uninterrupted traffic. Record continuous requests during a rollout.

The workflow updates an existing Deployment in the current/default namespace. It does not
provision the cluster, apply Secrets/ConfigMaps or create the initial Deployment. Manifest
changes need a separate apply. Reapplying the current deployment manifests selects `latest`,
which can replace a previously deployed SHA; check the resulting image and deploy the intended
SHA again when necessary.

Authentication uses **GitHub OIDC → IAM role** (no long-lived AWS keys in GitHub).

## One-time setup

Prerequisites on your machine:

- AWS credentials (`aws configure` or SSO)
- `gh auth login` with access to `posgraduacaofiapnet/*`
- Bash (WSL/Linux recommended on Windows), `aws`, `kubectl`, `gh`, `python3`
- `curl`, `tar` and download access if `provision-eks.sh` needs to install `eksctl`

The scripts create/update cloud resources, IAM policies and repository settings. Check AWS
identity, region and `kubectl config current-context` before running. The cluster creation uses
`aws/eksctl-cluster.yaml`: keep its name/region consistent with `CLUSTER_NAME`/`AWS_REGION`.

```bash
cd FCG-Orchestration
export AWS_REGION=us-east-1
export CLUSTER_NAME=fcg-eks

./scripts/provision-cicd.sh   # ECR + OIDC IAM role + GitHub secrets
./scripts/provision-eks.sh    # create/reuse EKS and grant deploy role

# First run creates missing local secret files and stops on placeholders.
# Edit those gitignored files, then rerun:
./scripts/apply-k8s-secrets.sh

# Infra only (secrets are NOT in this kustomization)
kubectl apply -k k8s
kubectl wait --for=condition=complete job/fcg-database-init --timeout=180s
kubectl apply -f k8s/gateway/kong-config.yaml
kubectl apply -f k8s/gateway/kong-deployment.yaml
kubectl apply -f k8s/gateway/kong-service.yaml

# APIs — never apply *.example.yaml (it would overwrite live secrets)
./scripts/apply-api-manifests.sh
```

`provision-cicd.sh` also rewrites ECR registry placeholders in sibling API deployment manifests;
review its local diff. It does not create the outbox workers, SQS/Lambda/DynamoDB or monitoring.
Those resources require their own setup. Confirm that the initial ECR images exist before
expecting API pods to become Ready.

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

This policy describes the Kubernetes runtime files. Fixed development values remain in
appsettings, Compose, Kong configuration and seed/test settings; the Phase 4 zero-hardcoded
credentials requirement is not fully resolved. Removing Secret YAMLs from tracking does not
remove credentials from Git history. See [FASE4.md](FASE4.md).

Do **not** run `kubectl apply -f ../FCG-*/k8s/` — that would include `secret.example.yaml` and can wipe real credentials.

## Cost note

Cloud resources can incur ongoing charges; this document does not assume Free Tier eligibility
or a fixed hourly price. After assessment, if the environment is no longer needed, back up data
and confirm the target before deleting it. The following is a cleanup reference, not part of setup:

```bash
eksctl delete cluster --name fcg-eks --region us-east-1
```
