# FCG Orchestration — Fase 3

Infraestrutura local e Kubernetes do FIAP Cloud Games. A solução usa Kong como gateway, SQL Server,
RabbitMQ, Redis, MongoDB, Prometheus/Grafana, dois processos do worker genérico de outbox e uma
Lambda acionada por SQS.

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
DynamoDB no LocalStack.

### Imagens publicadas com AWS real

Use o overlay de produção para executar as imagens `latest` publicadas no GHCR e enviar os eventos de
notificação ao SQS real da AWS. Bancos, Redis, RabbitMQ, Kong e monitoramento continuam locais; o
LocalStack não é iniciado. A Lambda implantada na AWS deve estar associada à fila informada.

O arquivo de credenciais deve permanecer fora do Git. Ele precisa conter estas variáveis:

| Variável | Finalidade |
|---|---|
| `AWS_ACCESS_KEY_ID` | Identificador da credencial AWS usada pelos workers |
| `AWS_SECRET_ACCESS_KEY` | Segredo da credencial AWS usada pelos workers |
| `AWS_SESSION_TOKEN` | Token opcional para credenciais temporárias |
| `AWS_DEFAULT_REGION` | Região da fila SQS e da Lambda |
| `SQS_NOTIFICATIONS_QUEUE_URL` | URL completa da fila consumida pela Lambda |

Informe o caminho do arquivo privado de produção:

```powershell
$AwsEnvironmentFile = "C:\caminho\seguro\.env.production"
docker compose --env-file $AwsEnvironmentFile -f docker-compose.yml -f docker-compose.production.yml pull users-api catalog-api payments-api users-outbox-processor catalog-outbox-processor
docker compose --env-file $AwsEnvironmentFile -f docker-compose.yml -f docker-compose.production.yml up -d --no-build --force-recreate
```

Para padronizar o nome, também é possível copiar manualmente o arquivo para `.env.production`, que já
está ignorado pelo Git, e substituir `$AwsEnvironmentFile` por `.env.production` nos comandos.

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
