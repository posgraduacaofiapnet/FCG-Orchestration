#!/bin/bash

# =============================================================================
# FCG - End-to-End Test Script
# =============================================================================
# Prerequisites:
#   - jq installed (brew install jq)
#   - Services running via Docker Compose OR kubectl port-forward
#
# Usage:
#   chmod +x test.sh
#   ./test.sh
# =============================================================================

USERS_URL="http://localhost:5101"
CATALOG_URL="http://localhost:5102"

EMAIL="testuser@fcg.com"
PASSWORD="Senha@123"
NAME="FCG Tester"

echo ""
echo "============================================="
echo "  FCG - FIAP Cloud Games - E2E Test"
echo "============================================="

# -----------------------------------------------
# 1. REGISTER
# -----------------------------------------------
echo ""
echo ">>> [1/6] Registering user..."
REGISTER_RESPONSE=$(curl -s -X POST "$USERS_URL/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

echo "$REGISTER_RESPONSE" | jq .

USER_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.id // empty')

if [ -z "$USER_ID" ]; then
  echo "!! Register failed or user already exists. Trying login to get userId..."
fi

# -----------------------------------------------
# 2. LOGIN
# -----------------------------------------------
echo ""
echo ">>> [2/6] Logging in..."
LOGIN_RESPONSE=$(curl -s -X POST "$USERS_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

echo "$LOGIN_RESPONSE" | jq .

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.userId // .id // empty')

if [ -z "$TOKEN" ]; then
  echo "!! Login failed. Aborting."
  exit 1
fi

echo ""
echo "    User ID : $USER_ID"
echo "    Token   : ${TOKEN:0:40}..."

# -----------------------------------------------
# 3. CREATE GAME
# -----------------------------------------------
echo ""
echo ">>> [3/6] Creating game in catalog..."
GAME_RESPONSE=$(curl -s -X POST "$CATALOG_URL/api/games" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "title": "Cyber FIAP",
    "description": "Jogo demo para o fluxo de compra.",
    "price": 99.90
  }')

echo "$GAME_RESPONSE" | jq .

GAME_ID=$(echo "$GAME_RESPONSE" | jq -r '.id // empty')

if [ -z "$GAME_ID" ]; then
  echo "!! Could not create game. Aborting."
  exit 1
fi

echo ""
echo "    Game ID : $GAME_ID"

# -----------------------------------------------
# 4. PURCHASE GAME
# -----------------------------------------------
echo ""
echo ">>> [4/6] Purchasing game..."
PURCHASE_RESPONSE=$(curl -s -X POST "$CATALOG_URL/api/library/purchase" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"userId\":\"$USER_ID\",\"gameId\":\"$GAME_ID\"}")

echo "$PURCHASE_RESPONSE" | jq .

# -----------------------------------------------
# 5. WAIT FOR EVENTS
# -----------------------------------------------
echo ""
echo ">>> [5/6] Waiting 3s for RabbitMQ events to process..."
sleep 3

# -----------------------------------------------
# 6. CHECK LIBRARY
# -----------------------------------------------
echo ""
echo ">>> [6/6] Checking user library..."
LIBRARY_RESPONSE=$(curl -s -X GET "$CATALOG_URL/api/library/$USER_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "$LIBRARY_RESPONSE" | jq .

# -----------------------------------------------
# SUMMARY
# -----------------------------------------------
echo ""
echo "============================================="
echo "  DONE"
echo "============================================="
echo "  User ID : $USER_ID"
echo "  Game ID : $GAME_ID"
echo ""
echo "  Check event logs:"
echo "  - docker compose logs notifications_api"
echo "  - docker compose logs payments_api"
echo ""
echo "  Or on Kubernetes:"
echo "  - kubectl logs deployment/notifications-api"
echo "  - kubectl logs deployment/payments-api"
echo "============================================="
