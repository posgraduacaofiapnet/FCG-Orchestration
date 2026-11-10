# FCG Orchestration - preparação da Fase 4

Infraestrutura local e Kubernetes do FIAP Cloud Games. A solução usa Kong como gateway, SQL Server,
RabbitMQ, Redis, MongoDB, Prometheus/Grafana, dois processos do worker genérico de outbox e uma
Lambda acionada por SQS.

## Documentação da Fase 4

Esta é a documentação central da evolução do FCG. A branch principal dos repositórios é `master`.
A solução contém recursos já implementados e pendências para a entrega; os manifests e o modo
híbrido com AWS não comprovam, por si, uma implantação em Kubernetes gerenciado.

- [Requisitos, situação e pendências da Fase 4](docs/FASE4.md)
- [Arquitetura, fluxos e persistência poliglota](docs/ARQUITETURA.md)
- [Procedimentos de validação e evidências](docs/VALIDACAO.md)
- [Relatório de entrega em Markdown](docs/RELATORIO-ENTREGA.md)
- [Relatório de entrega em TXT](docs/RELATORIO-ENTREGA.txt)

Revisão de 10/11/2026: MongoDB e Redis estão integrados ao CatalogAPI na `master`. A busca está
nas branches `feature/elasticsearch` de CatalogAPI e Orchestration, ainda fora da principal.
As pipelines de UsersAPI e CatalogAPI testam e publicam imagens `latest` no GHCR, sem deploy no
cluster. Registry nativo da nuvem, tags versionadas, segredos sem valores fixos, serviço de busca
gerenciado e execução cloud ainda precisam ser concluídos ou comprovados.

## Repositórios lado a lado

```text
FIAP/
├── FCG-UsersAPI/
├── FCG-CatalogAPI/
├── FCG-PaymentsAPI/
├── FCG-Outbox-Processor/
├── FCG-Notifications-Lambda/
└── FCG-Orchestration/
```

São necessários os seis repositórios acima. `FCG-NotificationsAPI` é legado da Fase 2 e não está
no Compose atual; `FCG-Tech-Challenge` preserva o monólito/staging e não é a fonte dos serviços.
Na revisão local de 10/11/2026, Outbox Processor e Notifications Lambda ainda não estavam clonados.
Sem eles, os contextos de build dos workers e o empacotamento da Lambda não ficam disponíveis.

Pré-requisitos: Git, SDK .NET 10, Docker com Compose e PowerShell para os scripts. O modo híbrido
precisa de uma versão do Compose que aceite `!reset` e `!override`. Kubernetes exige `kubectl`,
contexto configurado e infraestrutura previamente preparada; os arquivos locais não criam o cluster cloud.

## Comunicação

```text
Cliente -> Kong -> UsersAPI ----SQL transaction----> User + UserCreated outbox
                    |                                      |
Cliente -> Kong -> CatalogAPI --SQL transaction----> Order + SQS outbox + MassTransit outbox
                    |                ^                     |
                    v                |                     v
                 RabbitMQ ------ PaymentsAPI       Outbox Processor (por banco)
                    |                                      |
                    +-> CatalogAPI -> PaymentProcessed outbox
                                                           |
                                                           v
                                                          SQS
                                                           |
                                                           v
                                             Notifications Lambda
                                      (3 services + idempotência DynamoDB)
```

O RabbitMQ continua restrito ao fluxo de pagamento da Fase 2. Todos os eventos de notificação da
Fase 3 seguem pelo outbox SQL e SQS. A mensagem Catalog → RabbitMQ é entregue pelo Bus Outbox do
MassTransit, armazenado nas tabelas do schema `messaging` no `FCGCatalogDb`.

## Tabela de outbox

| Coluna | Tipo SQL | Regra |
|---|---|---|
| `Id` | `uniqueidentifier` | PK e chave idempotente do evento |
| `EventType` | `nvarchar(100)` | `UserCreated`, `OrderPlaced` ou `PaymentProcessed` |
| `IsSuccessful` | `bit` | `0` na inserção; `1` após publicação |
| `CreatedAt` | `datetimeoffset` | data UTC de inserção |
| `Payload` | `nvarchar(max)` | evento completo serializado em JSON |
| `NextAttemptAt` | `datetimeoffset null` | nulo na inserção; UTC + 15 min em falha/lease |
| `Attempts` | `int` | incrementado antes de toda tentativa, inclusive sucesso |

O índice filtrado de pendências começa por `NextAttemptAt`, seguido de `CreatedAt` e `Id`; um segundo
índice filtrado atende a limpeza dos registros concluídos. Apenas registros com `Attempts < 10`
permanecem elegíveis. Constraints validam tentativa, JSON e tipo.

O MassTransit usa estruturas separadas:

| Tabela | Responsabilidade |
|---|---|
| `messaging.InboxState` | Estado de idempotência dos consumidores MassTransit |
| `messaging.OutboxMessage` | Envelope destinado ao RabbitMQ |
| `messaging.OutboxState` | Controle da entrega do Bus Outbox |

## Ordem garantida do banco

Os scripts em `k8s/database/scripts` criam os dois bancos, todos os objetos de domínio e a outbox.
Eles são idempotentes e também fazem a evolução `UserEmail` em bancos existentes.

No Docker Compose, as APIs e workers dependem de `database-init` com
`condition: service_completed_successfully`. No Kubernetes:

```bash
kubectl apply -k k8s
kubectl wait --for=condition=complete job/fcg-database-init --timeout=180s
```

Esses comandos partem da raiz deste repositório e aplicam somente os recursos listados em
`k8s/kustomization.yaml`. Gateway, monitoramento, APIs e workers não são incluídos automaticamente
por esse comando. A Lambda também tem implantação separada. Conferir o contexto/namespace antes
de aplicar e configurar as credenciais conforme a política do ambiente.

Os deployments das APIs possuem `initContainer` adicional, portanto o container da aplicação não
inicia sem o ConfigMap dos scripts e sem a aplicação bem-sucedida do seu schema.

## Execução local

O comando abaixo empacota a Lambda, recria o ambiente local, aguarda todas as dependências e valida
o fluxo completo, inclusive outbox, RabbitMQ, SQS/LocalStack, Lambda e DynamoDB:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-apis.ps1 -StartDocker
```

Para apenas construir e iniciar os componentes, execute `start-local.ps1` com a mesma política de
execução. Nenhuma credencial AWS é necessária no modo local. As variáveis opcionais para uma conta
AWS real estão documentadas em `.env.example`.

O script gera `.artifacts/fcg-notifications.zip` a partir do repositório da Lambda antes de subir
o LocalStack. Na primeira execução, prefira o script: `docker compose up --build` sozinho não gera
esse pacote. A preparação recria containers, e a validação cria dados de teste. O Compose atual
contém credenciais fixas de desenvolvimento e não é uma configuração final de segurança da Fase 4.

| Componente | Endereço local |
|---|---|
| Kong | `http://localhost:8000` |
| UsersAPI | `http://localhost:5101` |
| CatalogAPI | `http://localhost:5102` |
| PaymentsAPI | `http://localhost:5103` |
| Users outbox | `http://localhost:5104/health/ready` |
| Catalog outbox | `http://localhost:5105/health/ready` |
| RabbitMQ | `http://localhost:15672` |
| LocalStack (SQS/Lambda/DynamoDB) | `http://localhost:4566` |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3000` |

## Dois modos de teste

### Código local

Use o arquivo principal quando precisar validar alterações ainda não publicadas. As quatro aplicações
são compiladas diretamente dos repositórios locais posicionados ao lado do Orchestration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-apis.ps1 -StartDocker
```

Esse modo usa apenas `docker-compose.yml`, executa `docker compose up --build` e mantém SQS, Lambda e
DynamoDB no LocalStack. As credenciais `test`, a fila e o endpoint local são definidos diretamente
nesse arquivo, portanto o modo local não lê nem depende das credenciais AWS do `.env`.

### Imagens publicadas com AWS real

Use o overlay de produção para executar as imagens `latest` publicadas no GHCR e enviar os eventos de
notificação ao SQS real da AWS. Bancos, Redis, RabbitMQ, Kong e monitoramento continuam locais; o
LocalStack não é iniciado. A Lambda implantada na AWS deve estar associada à fila informada.

O arquivo de credenciais deve ser salvo como `.env` na raiz do Orchestration e permanecer fora do
Git. O Docker Compose o carrega automaticamente. Ele precisa conter estas variáveis:

| Variável | Finalidade |
|---|---|
| `AWS_ACCESS_KEY_ID` | Identificador da credencial AWS usada pelos workers |
| `AWS_SECRET_ACCESS_KEY` | Segredo da credencial AWS usada pelos workers |
| `AWS_SESSION_TOKEN` | Token opcional para credenciais temporárias |
| `AWS_REGION` | Região da fila SQS e da Lambda |
| `SQS_NOTIFICATIONS_QUEUE_URL` | URL completa da fila consumida pela Lambda |

Execute o modo de produção a partir da raiz do Orchestration:

```powershell
docker compose -f docker-compose.yml -f docker-compose.production.yml pull users-api catalog-api payments-api users-outbox-processor catalog-outbox-processor
docker compose -f docker-compose.yml -f docker-compose.production.yml up -d --no-build --force-recreate
```

O `.gitignore` exclui `.env` e `.env.production`; somente `.env.example`, sem valores reais, é
versionado como referência das nomenclaturas esperadas.

## Collection Postman da Fase 3

O nome do arquivo foi preservado para compatibilidade. A coleção continua útil como validação
funcional da base da Fase 4, mas não comprova busca avançada, desempenho ou deploy cloud.

Importe `postman/FCG-Phase3.postman_collection.json` e execute a collection completa pelo Collection
Runner. Todas as chamadas externas de Users e Catalog usam o Kong em `http://localhost:8000`.

A collection cria um usuário e um jogo, valida JWT, cache Redis, compra/pagamento, avaliações no
MongoDB e aguarda os eventos `OrderPlaced` e `PaymentProcessed`. A validação final chama o endpoint
administrativo `GET /api/notifications/status`, que cruza o outbox SQL com o status `Completed`
gravado pela Lambda no DynamoDB. Nenhuma credencial AWS fica armazenada na collection.

O operador `!reset` remove os blocos `build` herdados. O `Outbox__ServiceUrl` vazio faz o AWS SDK usar
o endpoint real da região, enquanto o `!override` remove a dependência dos workers em relação ao
LocalStack. Não execute `test-apis.ps1` neste modo: o roteiro cria dados e mensagens de teste e valida
recursos exclusivos do ambiente LocalStack.

As imagens utilizadas são:

| Serviço | Imagem |
|---|---|
| UsersAPI | `ghcr.io/posgraduacaofiapnet/fcg-users-api:latest` |
| CatalogAPI | `ghcr.io/posgraduacaofiapnet/fcg-catalog-api:latest` |
| PaymentsAPI | `ghcr.io/posgraduacaofiapnet/fcg-payments-api:latest` |
| Workers de outbox | `ghcr.io/posgraduacaofiapnet/fcg-outbox-processor:latest` |

O arquivo `docker-compose.production.yml` não cria a fila nem implanta a Lambda. Esses recursos
continuam sendo entregues pelo template SAM de `FCG-Notifications-Lambda`; o Compose apenas publica
na fila já existente por meio dos dois workers de outbox.
