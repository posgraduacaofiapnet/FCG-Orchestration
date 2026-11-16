# Validação e evidências da Fase 4

Procedimento para executar e registrar resultados. Revisão documental em 16/11/2026 por leitura
do código. A seção **Registro cloud (11/11/2026)** preserva os resultados informados na revisão
anterior; não foram repetidos nem conferidos ao vivo nesta tarefa.

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
2. Com JWT de usuário, `POST /api/games/{id}/reviews` e `GET /api/games/{id}/reviews`.
   O código exige jogo ativo e autenticação para criar; não exige compra prévia.
3. Conferir collection `reviews` no Mongo (`Mongo__Database=fcg_catalog`) e índice por `gameId`.

## Evidência de cache e desempenho

Confirmar `ConnectionStrings__Redis=redis:6379`. Medir listagem fria vs aquecida e registrar abaixo.
Usar os mesmos parâmetros, dados e concorrência, repetir as medições e separar aquecimento do
processo/conexões do efeito do cache. Conferir logs hit/miss e chaves `fcg:`; fallback em memória
local não comprova cache distribuído. Criar/editar/desativar jogo deve invalidar a listagem.

| Data / ambiente / revisão | Consulta e volume | Amostras | Sem hit (ms) | Com hit (ms) | Evidência Redis/logs |
|---|---|---|---|---|---|
| A preencher após medição | GET `/api/games?page=1&pageSize=10` | A preencher | Não medido | Não medido | A anexar |

## Evidência de busca

1. Criar/editar jogo e localizar em `/search?q=...` (resposta com `score`).
2. Validar obrigatoriamente tolerância a erro de digitação e ordenação por relevância com
   resultados concorrentes. A consulta exata `Cyber` presente na regressão não prova fuzzy search.
3. Soft-delete e confirmar ausência; `POST /api/games/reindex` e nova busca.
4. Motor em uso: Elasticsearch **no EKS** (`elasticsearch:9200`), índice `fcg-games` — não é Amazon OpenSearch Service.
   Isso não comprova a exigência de serviço de busca gerenciado do enunciado.

## Evidência cloud e entrega contínua

1. Provedor AWS, região `us-east-1`, cluster `fcg-eks`, registry ECR `fcg-*-api`.
2. `kubectl config current-context` → `arn:aws:eks:us-east-1:174302433776:cluster/fcg-eks`
3. Registrar `kubectl get nodes`, `kubectl get deployments`, `kubectl get pods` e `kubectl get services`
   no namespace utilizado, sem Secrets. A barra vertical não deve ser copiada como pipe entre comandos.
4. Imagens tagueadas com SHA; pipeline: testes → build/push ECR → Trivy → rolling update EKS.
5. `kubectl rollout status deployment/users-api` (e catalog/payments) após merge na `master`.
6. Durante rollout, registrar requisições contínuas, códigos HTTP e latências na URL pública.
   Rollback: selecionar imagem SHA anterior existente no ECR com `kubectl set image` e aguardar
   `kubectl rollout status`. Reexecutar workflow antigo também recompila e republica; não equivale
   necessariamente a restaurar o mesmo digest. Registrar a revisão para manter código e ambiente coerentes.
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

As linhas acima são registros de 11/11; disponibilidade atual, tráfego durante rollout e busca
com erro de digitação não foram verificados por esta revisão de documentação. Os checks de
busca de `test.sh` e Bruno consultam `Cyber`, sem erro de digitação.

## Fechamento da documentação

- [x] Atualizar a [matriz](FASE4.md) com resultados comprovados em nuvem.
- [x] Preencher Grupo 05, integrantes, RM e Discord no relatório, conforme o modelo da Fase 3 fornecido pelo grupo.
- [x] Registrar URLs públicas, commits e links de pipelines sem segredos.
- [ ] Publicar esta revisão documental de 16/11 e conferir acesso do avaliador. A base de 11/11 já está versionada na `master`.
- [ ] Anexar ganho de cache, fuzzy search, relevância e tráfego contínuo durante rollout.
- [ ] Resolver ou registrar formalmente a exigência de busca gerenciada e os valores fixos remanescentes.
- [x] Incluir no relatório o link da apresentação fornecido pelo grupo: [YouTube](https://www.youtube.com/watch?v=yLbDMeNDyHM). Conteúdo, duração e permissões de acesso não foram conferidos nesta atualização.
- [ ] Revisar o relatório final para remover campos “a preencher” de identificação antes da submissão.
