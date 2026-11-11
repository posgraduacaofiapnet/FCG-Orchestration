# FCG - Tech Challenge Fase 4

Referência de requisitos e situação da implementação em **11/11/2026**. Base: enunciado `TC NETT - Fase 4.pdf`, páginas 2 a 6, e código na `master` dos repositórios, com execução comprovada no cluster AWS EKS `fcg-eks` (região `us-east-1`). O PDF é material da disciplina e não é distribuído neste repositório.

Código implementado, configuração disponível e evidência de funcionamento em nuvem são tratados na [validação](VALIDACAO.md) e no [relatório](RELATORIO-ENTREGA.md).

## Documentação da entrega

- [README e execução](../README.md)
- [Arquitetura e persistência](ARQUITETURA.md)
- [CI/CD GitHub Actions + EKS/ECR](CICD.md)
- [Validação e coleta de evidências](VALIDACAO.md)
- [Relatório de entrega editável](RELATORIO-ENTREGA.md)
- [Relatório em TXT para submissão](RELATORIO-ENTREGA.txt)

## Matriz de requisitos

| Requisito do enunciado | Evidência atual | Situação / ação restante |
|---|---|---|
| Kubernetes gerenciado: EKS, AKS, GKE ou OKE | Cluster AWS EKS `fcg-eks` (versão **1.35**, status ACTIVE) em `us-east-1`, 2 nós Ready | Atendido. |
| Registry privado nativo da nuvem | Amazon ECR: `fcg-users-api`, `fcg-catalog-api`, `fcg-payments-api` | Atendido. Imagens em execução usam tag = SHA do commit. |
| Acesso externo por Load Balancer ou Ingress | Kong `LoadBalancer` com DNS ELB público | Atendido. Health e APIs respondem via Kong. |
| MongoDB ou DynamoDB com driver oficial .NET | CatalogAPI: `MongoDB.Driver` (avaliações) + DynamoDB para status de notificações; Mongo no cluster | Atendido funcionalmente. Mongo sem PVC nos manifests — melhorar persistência se exigido. |
| Cache distribuído | Redis no cluster; `ConnectionStrings__Redis=redis:6379` no ConfigMap | Atendido. Medição formal de latência cache hit/miss ainda pendente. |
| Busca em Elasticsearch/OpenSearch gerenciado | Elasticsearch **no cluster EKS** (`http://elasticsearch:9200`, índice `fcg-games`) + `/search` na `master` | Busca integrada e validada. Serviço é o motor no próprio EKS (não Amazon OpenSearch Service). |
| Atualizar índice ao inserir/editar jogos | Sincronização + `POST /api/games/reindex` na CatalogAPI | Validado no ambiente cloud (`indexedCount` e `/search` com o jogo criado). |
| `/search`, fuzzy search e relevância | Rotas Kong `/search` e `/api/games/search`; resposta com `score` | Validado (`./test.sh --aws` e Bruno 17/17). |
| CI/CD para UsersAPI e CatalogAPI | Workflows também cobrem PaymentsAPI: test → build → Trivy → ECR → EKS | Atendido. OIDC (sem Access Key fixa no GitHub). |
| Imagens com versionamento | Tag = git SHA (ex.: `.../fcg-catalog-api:43a8b59…`) | Atendido. |
| Rolling Update sem downtime | Deployments com `maxUnavailable: 0` e probes `/health` | Configurado e usado pelos deploys da pipeline. Evidência contínua de tráfego durante rollout pode ser anexada na demo. |
| Security scan | Trivy no workflow (não bloqueante) | Atendido como scan desejável. |
| Zero credenciais fixas no código/YAML | Secrets via `secretKeyRef` + arquivos locais gitignored; seed admin ainda documentado para demos | Parcial. Não versionar JWT/runtime; revisar valores de seed em envs Bruno se o avaliador exigir zero seed no git. |
| Código, manifests e pipelines versionados | Repos + `k8s/` + `docs/CICD.md` + scripts `provision-*.sh` / `apply-*.sh` | Atendido. |
| README detalhado e relatório com identificação/links | Docs + relatório | Preencher **identificação do grupo** e link do vídeo antes da submissão formal. |

## Ambiente cloud registrado (11/11/2026)

| Item | Valor |
|---|---|
| Provedor / região | AWS / `us-east-1` |
| Cluster | `fcg-eks` (Kubernetes 1.35) |
| Registry | `174302433776.dkr.ecr.us-east-1.amazonaws.com/fcg-*-api` |
| Gateway público | `http://a552424fe85074122b9a67db27f844d5-1958877460.us-east-1.elb.amazonaws.com` |
| Busca | Elasticsearch in-cluster; Catalog `ConnectionStrings__Elasticsearch=http://elasticsearch:9200` |
| Regressão | `./test.sh --aws` e `./bruno/run-regression.sh AWS` |

## Commits de referência na `master` (revisão 11/11/2026)

| Repositório | Commit |
|---|---|
| FCG-UsersAPI | `e936e82` |
| FCG-CatalogAPI | `43a8b59` |
| FCG-PaymentsAPI | `6e8511b` |
| FCG-Orchestration | `329e41a` |

Pipelines verdes (push `master`): [Users](https://github.com/posgraduacaofiapnet/FCG-UsersAPI/actions/runs/42944332200), [Catalog](https://github.com/posgraduacaofiapnet/FCG-CatalogAPI/actions/runs/42944627944), [Payments](https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI/actions/runs/42944651919).

## Pendências restantes para submissão

1. Preencher nome do grupo, integrantes e Discord no relatório.
2. Anexar/medir evidência de latência Redis (hit vs miss) se o avaliador exigir números.
3. Completar o link do vídeo (fora desta atualização).
4. Após a avaliação, considerar `eksctl delete cluster --name fcg-eks --region us-east-1` para interromper custos.
