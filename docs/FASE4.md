# FCG - Tech Challenge Fase 4

Revisão documental de **16/11/2026**. Base: enunciado `TC NETT - Fase 4.pdf`, páginas 2 a 6,
código na `master` e registros de execução no AWS EKS `fcg-eks` (`us-east-1`) incluídos na
documentação de 11/11/2026. Esses registros foram preservados, mas o ambiente e as execuções
remotas não foram consultados novamente nesta revisão. O PDF não é distribuído neste repositório.

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
| Cache distribuído | Redis no cluster; `ConnectionStrings__Redis=redis:6379` no ConfigMap | Implementado. Demonstrar impacto positivo na resposta é parte da entrega; evidência comparativa de latência hit/miss ainda pendente. |
| Busca em Elasticsearch/OpenSearch gerenciado | Elasticsearch **no cluster EKS** (`http://elasticsearch:9200`, índice `fcg-games`) + `/search` na `master` | Parcial: busca implementada, mas o motor em Deployment próprio não é serviço de busca gerenciado. Adequar ou confirmar a alternativa com a disciplina. |
| Atualizar índice ao inserir/editar jogos | Sincronização + `POST /api/games/reindex` na CatalogAPI | Validado no ambiente cloud (`indexedCount` e `/search` com o jogo criado). |
| `/search`, fuzzy search e relevância | Rotas Kong `/search` e `/api/games/search`; código fuzzy `AUTO`, score descendente | Implementado. A regressão registrada busca `Cyber`; anexar cenário com erro de digitação e comparação de relevância. Retornar score não comprova sozinho fuzzy search. |
| CI/CD para UsersAPI e CatalogAPI | Workflows também cobrem PaymentsAPI: testes → build/push ECR → Trivy → EKS | Implementado, com execuções de sucesso registradas em 11/11. OIDC, sem Access Key fixa no GitHub. |
| Imagens com versionamento | Tag = git SHA (ex.: `.../fcg-catalog-api:43a8b59…`) | Atendido. |
| Rolling Update sem downtime | Deployments com 2 réplicas, `maxUnavailable: 0` e probes `/health` | Configurado. Registrar tráfego contínuo durante rollout para comprovar ausência de indisponibilidade; sucesso do rollout sozinho não basta. |
| Security scan | Trivy no workflow (não bloqueante) | Atendido como scan desejável. |
| Zero credenciais fixas no código/YAML | Secrets de runtime agora locais e ignorados; modelos com placeholders versionados | Parcial. Persistem valores fixos em appsettings, Compose, Kong e seed/testes. A exigência é explícita; remover valores remanescentes e revisar histórico/credenciais conforme uso. |
| Código, manifests e pipelines versionados | Repos + `k8s/` + `docs/CICD.md` + scripts `provision-*.sh` / `apply-*.sh` | Atendido. |
| README detalhado e relatório com identificação/links | Relatório do Grupo 05 com participantes, RM, Discord, documentação, repositórios e apresentação | Preenchido no formato do relatório anterior do grupo; conferir acesso aos links antes da submissão. |

## Ambiente cloud registrado (11/11/2026; não revalidado em 16/11)

| Item | Valor |
|---|---|
| Provedor / região | AWS / `us-east-1` |
| Cluster | `fcg-eks` (Kubernetes 1.35) |
| Registry | `174302433776.dkr.ecr.us-east-1.amazonaws.com/fcg-*-api` |
| Gateway público | `http://a552424fe85074122b9a67db27f844d5-1958877460.us-east-1.elb.amazonaws.com` |
| Busca | Elasticsearch in-cluster; Catalog `ConnectionStrings__Elasticsearch=http://elasticsearch:9200` |
| Regressão | `./test.sh --aws` e `./bruno/run-regression.sh AWS` |

## Commits registrados no ambiente em 11/11/2026

Esta tabela preserva a revisão da evidência histórica, não identifica automaticamente o HEAD
atual nem a versão em execução hoje. O checkout de 16/11 contém Catalog `36080e0` e
Orchestration `0884f4d`, posteriores aos commits abaixo.

| Repositório | Commit |
|---|---|
| FCG-UsersAPI | `e936e82` |
| FCG-CatalogAPI | `43a8b59` |
| FCG-PaymentsAPI | `6e8511b` |
| FCG-Orchestration | `329e41a` |

Pipelines verdes (push `master`): [Users](https://github.com/posgraduacaofiapnet/FCG-UsersAPI/actions/runs/42944332200), [Catalog](https://github.com/posgraduacaofiapnet/FCG-CatalogAPI/actions/runs/42944627944), [Payments](https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI/actions/runs/42944651919).

## Pendências restantes para submissão

1. Conferir os dados do Grupo 05 e os links do relatório, preenchidos a partir do modelo de entrega da Fase 3 fornecido pelo grupo.
2. Demonstrar e registrar o ganho de latência Redis (hit vs miss), sem tratar isso como opcional.
3. Adequar o motor de busca para serviço gerenciado ou confirmar a alternativa com a disciplina.
4. Remover credenciais fixas remanescentes do código/configuração; manter apenas modelos sem valores reais.
5. Anexar busca com erro de digitação, relevância e tráfego contínuo durante rollout.
6. Conferir a revisão final entregue e os links de evidência, incluindo acesso à apresentação já informada no relatório.
7. Avaliar persistência/recuperação dos bancos sem PVC; é uma limitação operacional, não um item expressamente nomeado como PVC no enunciado.
8. Após a avaliação, considerar a limpeza dos recursos somente quando não forem mais necessários, conforme [CICD.md](CICD.md).
