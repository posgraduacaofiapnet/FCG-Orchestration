#!/usr/bin/env bash
# =============================================================================
# FCG - executa todas as requisicoes HTTP das APIs (Fase 2)
# =============================================================================
# Pre-requisitos:
#   - curl
#   - jq  (brew install jq  |  apt-get install jq)
#   - APIs no ar via Docker Compose, kubectl port-forward ou dotnet run
#
# Uso:
#   chmod +x test.sh
#   ./test.sh
#   ./test.sh --start-docker
#   GATEWAY_URL=http://localhost:8000 ./test.sh
# =============================================================================
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8000}"
USERS_URL="${USERS_URL:-$GATEWAY_URL}"
CATALOG_URL="${CATALOG_URL:-$GATEWAY_URL}"
USERS_HEALTH_URL="${USERS_HEALTH_URL:-$GATEWAY_URL/health/users}"
CATALOG_HEALTH_URL="${CATALOG_HEALTH_URL:-$GATEWAY_URL/health/catalog}"
PAYMENTS_URL="${PAYMENTS_URL:-http://localhost:5103}"
NOTIFICATIONS_URL="${NOTIFICATIONS_URL:-http://localhost:5104}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@fcg.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-AdminSenha@123}"
USER_NAME="${USER_NAME:-Joao Silva}"
USER_EMAIL="${USER_EMAIL:-tester-$(date +%Y%m%d%H%M%S)@fcg.com}"
USER_PASSWORD="${USER_PASSWORD:-Senha@123}"
CORRELATION_ID="${CORRELATION_ID:-demo-video-001}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
PURCHASE_WAIT="${PURCHASE_WAIT:-5}"
START_DOCKER=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --start-docker) START_DOCKER=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "curl nao encontrado." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq nao encontrado. Instale com: brew install jq   ou   apt-get install jq" >&2
  exit 1
fi

PASSED=0
FAILED=0

step() {
  echo ""
  echo ">>> $*"
}

request() {
  local expected="$1"
  local method="$2"
  local url="$3"
  local token="${4:-}"
  local body="${5:-}"

  local args=(-sS -w "\n%{http_code}" -X "$method" "$url"
    -H "Accept: application/json"
    -H "X-Correlation-ID: $CORRELATION_ID")

  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  local raw
  raw="$(curl "${args[@]}")"
  local status="${raw##*$'\n'}"
  local payload="${raw%$'\n'*}"

  if [[ "$status" == "$expected" ]]; then
    echo "    [OK]   $method $url  ->  $status" >&2
    PASSED=$((PASSED + 1))
  else
    echo "    [FAIL] $method $url  ->  $status (esperado $expected)" >&2
    FAILED=$((FAILED + 1))
    echo "$payload" | jq . 2>/dev/null || echo "$payload" >&2
    return 1
  fi

  if [[ -n "$payload" ]]; then
    echo "$payload" | jq . >&2 2>/dev/null || echo "$payload" >&2
  fi
  printf '%s' "$payload"
}

wait_health() {
  local name="$1"
  local url="$2"
  local timeout="$3"
  local elapsed=0

  echo "    Aguardando $name em $url ..."
  until curl -sf "$url" >/dev/null 2>&1; do
    sleep 3
    elapsed=$((elapsed + 3))
    if (( elapsed >= timeout )); then
      echo "$name nao respondeu em ${timeout}s." >&2
      exit 1
    fi
  done
  echo "    $name pronto."
}

if (( START_DOCKER == 1 )); then
  step "Subindo Docker Compose (docker compose up --build -d)"
  (cd "$SCRIPT_DIR" && docker compose up --build -d)
fi

echo ""
echo "============================================="
echo "  FCG - FIAP Cloud Games - Teste das APIs"
echo "============================================="
echo "  CorrelationId : $CORRELATION_ID"
echo "  Gateway       : $GATEWAY_URL"
echo "  User email    : $USER_EMAIL"

step "[1/12] Health checks"
wait_health "UsersAPI" "$USERS_HEALTH_URL" "$HEALTH_TIMEOUT"
wait_health "CatalogAPI" "$CATALOG_HEALTH_URL" "$HEALTH_TIMEOUT"
wait_health "PaymentsAPI" "$PAYMENTS_URL/health" "$HEALTH_TIMEOUT"
wait_health "NotificationsAPI" "$NOTIFICATIONS_URL/health" "$HEALTH_TIMEOUT"

request 200 GET "$USERS_HEALTH_URL" >/dev/null
request 200 GET "$CATALOG_HEALTH_URL" >/dev/null
request 200 GET "$PAYMENTS_URL/health" >/dev/null
request 200 GET "$NOTIFICATIONS_URL/health" >/dev/null

step "[2/12] POST /api/auth/register  (UsersAPI — publica UserCreatedEvent)"
request 201 POST "$USERS_URL/api/auth/register" "" \
  "{\"name\":\"$USER_NAME\",\"email\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}" >/dev/null

step "[3/12] POST /api/auth/login  (usuario comum)"
LOGIN_USER="$(request 200 POST "$USERS_URL/api/auth/login" "" \
  "{\"email\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}")"
USER_TOKEN="$(echo "$LOGIN_USER" | jq -r '.token')"
USER_ID="$(echo "$LOGIN_USER" | jq -r '.userId')"
if [[ -z "$USER_TOKEN" || "$USER_TOKEN" == "null" || -z "$USER_ID" || "$USER_ID" == "null" ]]; then
  echo "Login do usuario nao retornou token/userId." >&2
  exit 1
fi
echo "    userId : $USER_ID"
echo "    token  : ${USER_TOKEN:0:40}..."

step "[4/12] POST /api/auth/login  (admin seed)"
LOGIN_ADMIN="$(request 200 POST "$USERS_URL/api/auth/login" "" \
  "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")"
ADMIN_TOKEN="$(echo "$LOGIN_ADMIN" | jq -r '.token')"
if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "Login do admin nao retornou token. Confirme o seed Admin__Email / Admin__Password." >&2
  exit 1
fi

step "[5/12] POST /api/games  (CatalogAPI — exige Admin)"
GAME="$(request 201 POST "$CATALOG_URL/api/games" "$ADMIN_TOKEN" \
  '{"title":"Cyber FIAP","description":"Jogo demo para o fluxo de compra.","price":99.90}')"
GAME_ID="$(echo "$GAME" | jq -r '.id')"
if [[ -z "$GAME_ID" || "$GAME_ID" == "null" ]]; then
  echo "Criacao do jogo nao retornou id." >&2
  exit 1
fi
echo "    gameId : $GAME_ID"

step "[6/12] GET /api/games?page=1&pageSize=10"
request 200 GET "$CATALOG_URL/api/games?page=1&pageSize=10" >/dev/null

step "[7/12] GET /api/games/{id}"
request 200 GET "$CATALOG_URL/api/games/$GAME_ID" >/dev/null

step "[8/12] PUT /api/games/{id}  (Admin)"
request 200 PUT "$CATALOG_URL/api/games/$GAME_ID" "$ADMIN_TOKEN" \
  '{"title":"Cyber FIAP - Remasterizado","description":"Jogo demo atualizado para o video.","price":79.90}' >/dev/null

step "[9/12] POST + DELETE /api/games/{id}  (soft delete, Admin)"
GAME_DEL="$(request 201 POST "$CATALOG_URL/api/games" "$ADMIN_TOKEN" \
  '{"title":"Jogo para Soft Delete","description":"Criado apenas para demonstrar o DELETE.","price":19.90}')"
GAME_DEL_ID="$(echo "$GAME_DEL" | jq -r '.id')"
request 204 DELETE "$CATALOG_URL/api/games/$GAME_DEL_ID" "$ADMIN_TOKEN" >/dev/null

step "[10/12] POST /api/library/purchase  (User — publica OrderPlacedEvent)"
request 202 POST "$CATALOG_URL/api/library/purchase" "$USER_TOKEN" \
  "{\"userId\":\"$USER_ID\",\"gameId\":\"$GAME_ID\"}" >/dev/null

step "[11/12] Aguardando ${PURCHASE_WAIT}s o fluxo RabbitMQ"
sleep "$PURCHASE_WAIT"

step "[12/12] GET /api/library/{userId}"
LIBRARY=""
for i in 1 2 3 4 5 6; do
  LIBRARY="$(request 200 GET "$CATALOG_URL/api/library/$USER_ID" "$USER_TOKEN")"
  COUNT="$(echo "$LIBRARY" | jq 'length')"
  if [[ "$COUNT" -gt 0 ]]; then
    break
  fi
  if [[ "$i" -lt 6 ]]; then
    echo "    Biblioteca ainda vazia (pagamento assincrono). Nova tentativa em 2s..."
    sleep 2
  fi
done

echo ""
echo "============================================="
echo "  Concluidos : $PASSED  |  Falhas : $FAILED"
echo "============================================="
echo "  User ID : $USER_ID"
echo "  Game ID : $GAME_ID"
echo "  Email   : $USER_EMAIL"
echo ""
echo "  Logs dos eventos (Docker):"
echo "    docker compose -f \"$SCRIPT_DIR/docker-compose.yml\" logs --tail=50 payments-api"
echo "    docker compose -f \"$SCRIPT_DIR/docker-compose.yml\" logs --tail=50 notifications-api"
echo "    docker compose logs | grep $CORRELATION_ID"
echo ""
echo "  Logs dos eventos (Kubernetes):"
echo "    kubectl logs deployment/payments-api --tail=50"
echo "    kubectl logs deployment/notifications-api --tail=50"
echo "============================================="

if (( FAILED > 0 )); then
  exit 1
fi
