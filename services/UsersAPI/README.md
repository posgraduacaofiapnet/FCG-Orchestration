# UsersAPI

Microsservico responsavel por cadastro, login, JWT e publicacao do evento `UserCreatedEvent`.

## Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /health`

## Eventos

- Publica: `UserCreatedEvent`

## Variaveis

- `ConnectionStrings__DefaultConnection`
- `Jwt__Key`
- `Jwt__Issuer`
- `Jwt__Audience`
- `RabbitMq__Host`
- `RabbitMq__Username`
- `RabbitMq__Password`

Esta pasta pode ser movida para um repositorio Git proprio.
