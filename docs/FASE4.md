# FCG - Tech Challenge Fase 4

Referência de requisitos e situação da implementação em **10/11/2026**. Base: enunciado `TC NETT - Fase 4.pdf`, páginas 2 a 6, e código disponível na branch principal `master` dos repositórios locais. O PDF é material da disciplina e não é distribuído neste repositório.

Este documento descreve a preparação da entrega. Não certifica execução em nuvem. Código implementado, configuração disponível e evidência de funcionamento são tratados separadamente.

## Documentação da entrega

- [README e execução](../README.md)
- [Arquitetura e persistência](ARQUITETURA.md)
- [Validação e coleta de evidências](VALIDACAO.md)
- [Relatório de entrega editável](RELATORIO-ENTREGA.md)
- [Relatório em TXT para submissão](RELATORIO-ENTREGA.txt)

## Matriz de requisitos

| Requisito do enunciado | Evidência atual | Situação / ação restante |
|---|---|---|
| Kubernetes gerenciado: EKS, AKS, GKE ou OKE | Manifests de aplicações e infraestrutura | Execução em cluster gerenciado não comprovada nesta revisão. Informar provedor, cluster e evidências. VM com containers manuais não atende. |
| Registry privado nativo da nuvem | Workflows publicam em `ghcr.io` | Pendente configurar registry da nuvem escolhida e autenticação de publicação/pull. GHCR não satisfaz essa exigência específica. |
| Acesso externo por Load Balancer ou Ingress | `k8s/gateway/kong-service.yaml` define `LoadBalancer` | Manifesto disponível; endereço público e acesso no cluster cloud pendentes de comprovação. |
| MongoDB ou DynamoDB com driver oficial .NET | CatalogAPI usa `MongoDB.Driver` em avaliações e AWS SDK na consulta de status | Implementado na `master`; validar integração e persistência no ambiente final. |
| Cache distribuído | Redis via `IDistributedCache` no CatalogAPI | Implementado na `master`; medir latência e confirmar uso do Redis no ambiente final. |
| Busca em Elasticsearch/OpenSearch gerenciado | Branch remota `feature/elasticsearch` em CatalogAPI e Orchestration | Código fora da `master`. Integrar, validar e configurar serviço gerenciado; o container da branch não comprova este requisito. |
| Atualizar índice ao inserir/editar jogos | Branch de busca contém sincronização, remoção e reindexação | Pendente integração e validação de falhas/reprocessamento. |
| `/search`, fuzzy search e relevância | Branch de busca contém `/search`, `/api/games/search`, fuzzy `AUTO` e ordenação por score | Disponível apenas na branch de busca; não anunciar esses endpoints como ativos na `master`. |
| CI/CD para UsersAPI e CatalogAPI | `.github/workflows/publish-container.yml` nos dois repositórios | Build implícito no `dotnet test`, testes e build/push Docker definidos. Falta deploy no cluster. |
| Imagens com versionamento | Workflows publicam somente `latest` e registram SHA em label | Pendente tag identificável por commit/versão e política de rollback. Label de revisão não substitui tag versionada. |
| Rolling Update sem downtime | Deployments e probes `/health` | Base disponível, mas sem demonstração de rollout sem indisponibilidade e sem etapa de deploy na pipeline. |
| Security scan | Não localizado nos workflows examinados | Desejável no enunciado; pendente. |
| Zero credenciais fixas no código/YAML | Existem Secrets e referências `secretKeyRef`, mas também valores fixos versionados | Pendente adequação. Base64 não protege segredo. Esta revisão altera somente documentação. |
| Código, manifests e pipelines versionados | Repositórios separados, Dockerfiles, K8s e workflows | Disponíveis, com as lacunas acima. Terraform/CloudFormation não são obrigatórios se forem entregues manifests, conforme as alternativas do enunciado. |
| README detalhado e relatório com identificação/links | Documentação central e relatórios neste diretório | Preencher identificação do grupo e links/evidências finais antes de submeter. |

O título “CI/CD Multi-Cloud” não especifica deploy simultâneo em várias nuvens: o detalhamento permite escolher um provedor. “GitOps” aparece como título, mas não há exigência nominal de Argo CD ou Flux. Esta é a interpretação usada no planejamento, sujeita à orientação docente.

## Implementação de busca ainda não integrada

Na revisão de 10/11/2026 foram encontradas estas branches remotas:

- CatalogAPI: `feature/elasticsearch`, com os commits `d821283` e `4f133e0` fora da `master`.
- Orchestration: `feature/elasticsearch`, com o commit `51e3a95` fora da `master`.

A branch do CatalogAPI contém cliente Elasticsearch, mapeamento com analyzer `brazilian`, peso maior para título, fuzzy search, score, sincronização de jogos e reindexação. A do Orchestration contém container Elasticsearch, rotas Kong e chamada de teste. A existência desses arquivos não comprova execução ou configuração de serviço gerenciado. Esta atualização documental não faz merge dessas branches.

## Preparação técnica restante

1. Disponibilizar os repositórios `FCG-Outbox-Processor` e `FCG-Notifications-Lambda` ao lado dos serviços para reproduzir a stack local completa.
2. Integrar a busca e validar criação, edição, exclusão lógica, reindexação e busca com erro de digitação.
3. Registrar o cluster gerenciado e o serviço de busca gerenciado escolhidos. Rever armazenamento persistente e disponibilidade dos bancos: o manifesto atual do MongoDB não define PVC.
4. Substituir registry/tags e completar a pipeline com deploy, verificação do rollout e procedimento de rollback.
5. Remover credenciais fixas do código/YAML e injetar segredos no runtime. Manter JWT coerente entre UsersAPI, CatalogAPI e Kong.
6. Executar a validação no ambiente final, preencher as evidências e atualizar esta matriz.
7. Completar o relatório com dados do grupo, revisão entregue e links de acesso.

## Limites desta revisão

Testes executados em 10/11/2026: UsersAPI com 16 aprovados; CatalogAPI com 36 aprovados e 1 ignorado. O teste MongoDB exige `FCG_TEST_MONGO_CONNECTION` e não foi executado contra um banco real nessa rodada. O restore reportou avisos NU1902/NU1903 para `System.Security.Cryptography.Pkcs` 9.0.4.

Não foram executados nesta revisão: stack Compose completa, testes de integração com Redis/MongoDB reais, benchmark de latência, deploy cloud ou inspeção das execuções remotas do GitHub Actions. O contexto Kubernetes local selecionado era `docker-desktop`; isso não exclui a existência de outro ambiente do grupo.

O vídeo continua sendo um entregável do enunciado, com limite de 25 minutos, mas sua preparação e gravação estão fora desta atualização. O relatório reserva somente um campo para o link futuro.
