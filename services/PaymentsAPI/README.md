# PaymentsAPI

Microsservico responsavel por consumir pedidos, simular pagamento e publicar o resultado.

## Endpoints

- `GET /health`

## Eventos

- Consome: `OrderPlacedEvent`
- Publica: `PaymentProcessedEvent`

## Variaveis

- `RabbitMq__Host`
- `RabbitMq__Username`
- `RabbitMq__Password`
- `RabbitMq__OrderPlacedQueue`
- `Payments__ForceRejected`

Esta pasta pode ser movida para um repositorio Git proprio.
