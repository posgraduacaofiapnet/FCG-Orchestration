# NotificationsAPI

Microsservico responsavel por simular envio de e-mails via logs de console.

## Endpoints

- `GET /health`

## Eventos

- Consome: `UserCreatedEvent`
- Consome: `PaymentProcessedEvent`

## Variaveis

- `RabbitMq__Host`
- `RabbitMq__Username`
- `RabbitMq__Password`
- `RabbitMq__UserCreatedQueue`
- `RabbitMq__PaymentProcessedQueue`

Esta pasta pode ser movida para um repositorio Git proprio.
