# Validação e evidências da Fase 4

Procedimento para executar e registrar resultados. A seção **Registro cloud (11/11/2026)** documenta o que já foi comprovado no EKS.

Não copiar credenciais, tokens JWT, kubeconfig ou conteúdo de Secrets para o relatório ou capturas.

## Pré-requisitos locais

Clonar como pastas irmãs UsersAPI, CatalogAPI, PaymentsAPI, Orchestration (e, para a stack Compose completa, Outbox Processor e Notifications Lambda). Instalar .NET 10, Docker Compose, `kubectl`, AWS CLI e (opcional) Bruno / Node para o runner da coleção.

## Testes automatizados

```powershell
dotnet test ./FCG-UsersAPI/tests/UsersAPI.UnitTests/UsersAPI.UnitTests.csproj --configuration Release
dotnet test ./FCG-CatalogAPI/tests/CatalogAPI.UnitTests/CatalogAPI.UnitTests.csproj --configuration Release
dotnet test ./FCG-PaymentsAPI/tests/PaymentsAPI.UnitTests/PaymentsAPI.UnitTests.csproj --configuration Release
```

Para o teste real de MongoDB:

```powershell
$env:FCG_TEST_MONGO_CONNECTION = 'mongodb://localhost:27017'
dotnet test ./FCG-CatalogAPI/tests/CatalogAPI.UnitTests/CatalogAPI.UnitTests.csproj --configuration Release --filter FullyQualifiedName~MongoGameReviewStoreIntegrationTests
Remove-Item Env:FCG_TEST_MONGO_CONNECTION
```

Registro local anterior (10/11/2026): UsersAPI 16 aprovados; CatalogAPI 36 aprovados e 1 ignorado (Mongo sem conexão).

## Stack local completa

Na raiz de `FCG-Orchestration`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./start-local.ps1
docker compose ps
powershell -NoProfile -ExecutionPolicy Bypass -File ./test-apis.ps1
```

Alternativas HTTP:

- `./test.sh` — regressão via Kong local (`localhost:8000`), inclui outbox health nas portas diretas
- Bruno ambiente `Docker`
- Postman: `postman/FCG-Phase3.postman_collection.json`

## Regressão cloud (Kong / EKS)

Com o cluster no ar e o DNS do Load Balancer em `bruno/environments/AWS.bru`:

```bash
./test.sh --aws
./bruno/run-regression.sh AWS
```

Cobertura: health Users/Catalog/Payments, register/login, CRUD de jogos, soft delete, reindex + `/search`, purchase, library, reviews.

## Evidência de NoSQL

1. Criar jogo (Admin) e registrar ID.
2. Após compra na biblioteca, `POST /api/games/{id}/reviews` e `GET /api/games/{id}/reviews`.
3. Conferir collection `reviews` no Mongo (`Mongo__Database=fcg_catalog`) e índice por `gameId`.

## Evidência de cache e desempenho

Confirmar `ConnectionStrings__Redis=redis:6379`. Medir listagem fria vs aquecida e registrar abaixo.

| Data / ambiente / revisão | Consulta e volume | Amostras | Sem hit (ms) | Com hit (ms) | Evidência Redis/logs |
|---|---|---|---|---|---|
| A preencher após medição | GET `/api/games?page=1&pageSize=10` | A preencher | Não medido | Não medido | A anexar |

## Evidência de busca

1. Criar/editar jogo e localizar em `/search?q=...` (resposta com `score`).
2. Validar fuzzy (ex.: consulta com erro de digitação, se desejado na demo).
3. Soft-delete e confirmar ausência; `POST /api/games/reindex` e nova busca.
4. Motor em uso: Elasticsearch **no EKS** (`elasticsearch:9200`), índice `fcg-games` — não é Amazon OpenSearch Service.

## Evidência cloud e entrega contínua

1. Provedor AWS, região `us-east-1`, cluster `fcg-eks`, registry ECR `fcg-*-api`.
2. `kubectl config current-context` → `arn:aws:eks:us-east-1:174302433776:cluster/fcg-eks`
3. Registrar `kubectl get nodes|deployments|pods|services` (sem Secrets).
4. Imagens tagueadas com SHA do commit; pipeline: testes → Trivy → push ECR → rolling update EKS.
5. `kubectl rollout status deployment/users-api` (e catalog/payments) após merge na `master`.
6. Rollback: redeploy da imagem SHA anterior do ECR (`kubectl set image` / re-run pipeline em commit anterior).
7. Ver [CICD.md](CICD.md).

## Registro cloud (11/11/2026)

| Verificação | Resultado |
|---|---|
| EKS `fcg-eks` 1.35 ACTIVE, 2 nós Ready | OK |
| Deployments: users/catalog/payments 2/2; kong, redis, mongo, sqlserver, rabbitmq, elasticsearch 1/1 | OK |
| Kong LB público respondendo `/health/users|catalog|payments` | OK (`Healthy`) |
| `/search?q=Cyber` retorna jogos com `score` | OK |
| `./test.sh --aws` | OK (12 checks, 0 falhas) |
| `./bruno/run-regression.sh AWS` | OK (17/17 assertions) |
| Pipeline Users `e936e82` | [sucesso](https://github.com/posgraduacaofiapnet/FCG-UsersAPI/actions/runs/42944332200) |
| Pipeline Catalog `43a8b59` | [sucesso](https://github.com/posgraduacaofiapnet/FCG-CatalogAPI/actions/runs/42944627944) |
| Pipeline Payments `6e8511b` | [sucesso](https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI/actions/runs/42944651919) |

URL pública (sem path secreto):

`http://a552424fe85074122b9a67db27f844d5-1958877460.us-east-1.elb.amazonaws.com`

## Fechamento da documentação

- [x] Atualizar a [matriz](FASE4.md) com resultados comprovados em nuvem.
- [ ] Preencher grupo, integrantes e Discord no relatório.
- [x] Registrar URLs públicas, commits e links de pipelines sem segredos.
- [ ] Publicar este pacote documental na `master` e conferir acesso do avaliador.
- [ ] Completar o campo de link do vídeo quando existir.
- [ ] Revisar o relatório final para remover campos “a preencher” de identificação antes da submissão.
