# Relatório de entrega - Tech Challenge Fase 4

- **Projeto:** FIAP Cloud Games (FCG)
- **Curso:** Pós-graduação FIAP - .NET
- **Revisão documental:** 16/11/2026

**Situação:** implementação revisada e registros cloud/CI/CD de 11/11 preservados; ambiente não revalidado nesta tarefa. Link da apresentação informado. Há pendências técnicas e de evidência, além da identificação do grupo.

## Identificação do grupo

**Nome do grupo:** A PREENCHER PELO GRUPO.

| Nome completo | Username no Discord |
|---|---|
| A PREENCHER - incluir uma linha por integrante | A PREENCHER |

## Documentação

- [Documentação principal](https://github.com/posgraduacaofiapnet/FCG-Orchestration/blob/master/README.md)
- [Escopo e matriz da Fase 4](https://github.com/posgraduacaofiapnet/FCG-Orchestration/blob/master/docs/FASE4.md)
- [Arquitetura](https://github.com/posgraduacaofiapnet/FCG-Orchestration/blob/master/docs/ARQUITETURA.md)
- [CI/CD](https://github.com/posgraduacaofiapnet/FCG-Orchestration/blob/master/docs/CICD.md)
- [Validação e evidências](https://github.com/posgraduacaofiapnet/FCG-Orchestration/blob/master/docs/VALIDACAO.md)

## Repositórios da solução

| Repositório | Papel |
|---|---|
| [FCG-UsersAPI](https://github.com/posgraduacaofiapnet/FCG-UsersAPI) | Cadastro, JWT e outbox de usuários |
| [FCG-CatalogAPI](https://github.com/posgraduacaofiapnet/FCG-CatalogAPI) | Catálogo, compra, biblioteca, Redis, MongoDB e busca Elasticsearch |
| [FCG-PaymentsAPI](https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI) | Pagamentos simulados via RabbitMQ |
| [FCG-Orchestration](https://github.com/posgraduacaofiapnet/FCG-Orchestration) | Infraestrutura EKS/Kong, regressão Bruno/`test.sh`, documentação |
| [FCG-Outbox-Processor](https://github.com/posgraduacaofiapnet/FCG-Outbox-Processor) | Publicação de notificações SQL → SQS |
| [FCG-Notifications-Lambda](https://github.com/posgraduacaofiapnet/FCG-Notifications-Lambda) | Notificações serverless |

## Síntese técnica

Microsserviços .NET 10 atrás do Kong, SQL Server, RabbitMQ/MassTransit, outbox transacional e notificações SQS/Lambda. CatalogAPI usa MongoDB (avaliações), Redis (cache da listagem) e Elasticsearch (fuzzy `/search` com score).

**CI/CD:** GitHub Actions (OIDC) → testes → build/push Amazon ECR (tags SHA e latest) → Trivy não bloqueante → rolling update no EKS (`maxUnavailable: 0`). Pipeline definida para Users, Catalog e Payments.

**Busca:** integrada na `master` do CatalogAPI; motor Elasticsearch executando **no cluster EKS** (não Amazon OpenSearch Service). Validado com reindex + `/search` no Load Balancer público.

Pendências: identificação do grupo; evidência de ganho do Redis, busca com erro
de digitação/relevância e tráfego contínuo durante rollout; motor de busca em serviço gerenciado
ou confirmação da alternativa in-cluster com a disciplina; remoção completa de credenciais fixas
remanescentes. Os manifests sem PVC também têm limitação de persistência/recuperação.

## Ambiente e evidências registrados em 11/11/2026

Registros históricos importados da documentação anterior, não repetidos nesta revisão. Os
commits abaixo identificam aquela evidência; Catalog `36080e0` e Orchestration `0884f4d` são as
revisões locais posteriores examinadas em 16/11, não uma declaração de versão hoje implantada.

| Informação | Valor |
|---|---|
| Provedor, região e cluster | AWS, `us-east-1`, EKS `fcg-eks` (Kubernetes **1.35**, ACTIVE) |
| Registry privado nativo | Amazon ECR `fcg-users-api`, `fcg-catalog-api`, `fcg-payments-api` |
| Elasticsearch | Deployment in-cluster `elasticsearch:9200`, índice `fcg-games` |
| URL pública | `http://a552424fe85074122b9a67db27f844d5-1958877460.us-east-1.elb.amazonaws.com` |
| Commits do registro histórico | Users `e936e82` · Catalog `43a8b59` · Payments `6e8511b` · Orchestration `329e41a` |
| Pipeline com deploy | [Users](https://github.com/posgraduacaofiapnet/FCG-UsersAPI/actions/runs/42944332200) · [Catalog](https://github.com/posgraduacaofiapnet/FCG-CatalogAPI/actions/runs/42944627944) · [Payments](https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI/actions/runs/42944651919) |
| Rollout | Deployments 2 réplicas; `maxUnavailable: 0`; imagens SHA acima em execução |
| MongoDB + busca | Reviews via Bruno/`test.sh --aws`; `/search?q=Cyber` retorna jogos com `score`. Teste com erro de digitação ainda a anexar. |
| Regressão | `./test.sh --aws` OK; `./bruno/run-regression.sh AWS` 17/17 |
| Medições de cache | Ainda a preencher (hit/miss) |

## Link do vídeo

**Apresentação no YouTube:** [Assistir à apresentação](https://www.youtube.com/watch?v=yLbDMeNDyHM).

Link fornecido pelo grupo; conteúdo e duração não foram conferidos nesta atualização. O limite do enunciado é de 25 minutos.

## Conferência para submissão

1. Preencher identificação do grupo e Discord.
2. Publicar esta documentação na `master` e confirmar acesso do avaliador aos repositórios.
3. Anexar capturas de Actions / `kubectl get` se solicitado (sem Secrets).
   Completar também as evidências e pendências técnicas da [matriz](FASE4.md), sem apresentar
   ganho de cache ou busca gerenciada como opcionais.
4. Manter [RELATORIO-ENTREGA.txt](RELATORIO-ENTREGA.txt) sincronizado.
5. Após a avaliação, desligar o cluster para conter custos (`docs/CICD.md`).
