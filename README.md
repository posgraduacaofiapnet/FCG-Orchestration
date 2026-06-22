# FCG Orchestration

Repositorio de orquestracao da Fase 2 do Tech Challenge FIAP Cloud Games.

Este repositorio centraliza a execucao local e Kubernetes dos quatro microsservicos:

- UsersAPI: cadastro, login, JWT e evento `UserCreatedEvent`.
- CatalogAPI: catalogo, compra, biblioteca e evento `OrderPlacedEvent`.
- PaymentsAPI: processamento simulado e evento `PaymentProcessedEvent`.
- NotificationsAPI: notificacoes simuladas por logs.

## Repositorios Individuais

- UsersAPI: https://github.com/posgraduacaofiapnet/FCG-UsersAPI
- CatalogAPI: https://github.com/posgraduacaofiapnet/FCG-CatalogAPI
- PaymentsAPI: https://github.com/posgraduacaofiapnet/FCG-PaymentsAPI
- NotificationsAPI: https://github.com/posgraduacaofiapnet/FCG-NotificationsAPI
- Orquestracao: https://github.com/posgraduacaofiapnet/FCG-Orchestration

## Tecnologias

- .NET 10
- Entity Framework Core 10
- SQL Server
- JWT Bearer
- FluentValidation
- Swagger / OpenAPI
- MassTransit + RabbitMQ
- Docker Compose
- Kubernetes

## Executando com Docker Compose

```bash
docker compose up --build
```

URLs:

- UsersAPI Swagger: http://localhost:5101/swagger
- CatalogAPI Swagger: http://localhost:5102/swagger
- PaymentsAPI Swagger: http://localhost:5103/swagger
- NotificationsAPI Swagger: http://localhost:5104/swagger
- RabbitMQ Management: http://localhost:15672 (`guest` / `guest`)
- SQL Server: `localhost,1433`

## Fluxo de Cadastro

1. Chame `POST http://localhost:5101/api/auth/register`.
2. O UsersAPI salva o usuario no SQL Server.
3. O UsersAPI publica `UserCreatedEvent` no RabbitMQ.
4. O NotificationsAPI consome o evento e registra no console o envio do e-mail.

Payload:

```json
{
  "name": "User",
  "email": "user@email.com",
  "password": "Senha@123"
}
```

## Fluxo de Compra

1. Crie um jogo em `POST http://localhost:5102/api/games`.
2. Solicite a compra em `POST http://localhost:5102/api/library/purchase`.
3. O CatalogAPI publica `OrderPlacedEvent`.
4. O PaymentsAPI consome o pedido e publica `PaymentProcessedEvent`.
5. O CatalogAPI adiciona o jogo a biblioteca quando o pagamento e aprovado.
6. O NotificationsAPI registra no console o e-mail de confirmacao.

Payload de jogo:

```json
{
  "title": "Cyber FIAP",
  "description": "Jogo demo para o fluxo de compra.",
  "price": 99.90
}
```

Payload de compra:

```json
{
  "userId": "GUID_DO_USUARIO",
  "gameId": "GUID_DO_JOGO"
}
```

Consultar biblioteca:

```http
GET http://localhost:5102/api/library/{userId}
```

## Kubernetes Local

Construa as imagens antes de aplicar os manifests:

```bash
docker build -t fcg-users-api:latest -f services/UsersAPI/Dockerfile .
docker build -t fcg-catalog-api:latest -f services/CatalogAPI/Dockerfile .
docker build -t fcg-payments-api:latest -f services/PaymentsAPI/Dockerfile .
docker build -t fcg-notifications-api:latest -f services/NotificationsAPI/Dockerfile .
```

Aplique os manifests:

```bash
kubectl apply -f k8s
kubectl get pods
kubectl get services
```

Para testar de fora do cluster:

```bash
kubectl port-forward service/users-api 5101:80
kubectl port-forward service/catalog-api 5102:80
```

## Evidencias para o Video

- Mostrar `docker compose up --build`.
- Mostrar Swagger das APIs.
- Executar cadastro e observar logs do NotificationsAPI.
- Executar compra e observar logs do PaymentsAPI e NotificationsAPI.
- Mostrar `kubectl apply -f k8s` e `kubectl get pods`.
