$usersUrl = 'http://localhost:5101'
$catalogUrl = 'http://localhost:5102'

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  GERANDO TRAFEGO E METRICAS (GRAFANA)   " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Login Admin
Write-Host "[1/6] Autenticando Administrador (200 OK)..." -ForegroundColor Yellow
$adminBody = '{"email":"admin@fcg.com","password":"AdminSenha@123"}'
$adminToken = (curl.exe -s -X POST "$usersUrl/api/auth/login" -H "Content-Type: application/json" -d $adminBody | ConvertFrom-Json).token
Write-Host "      Admin autenticado com sucesso."

# 2. Cadastro e Login de Jogador
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$email = "gamer_$ts@fcg.com"
Write-Host "[2/6] Cadastrando novo jogador $email (201 Created)..." -ForegroundColor Yellow
$regBody = "{`"name`":`"Gamer FIAP`",`"email`":`"$email`",`"password`":`"Senha@123`"}"
$userId = (curl.exe -s -X POST "$usersUrl/api/auth/register" -H "Content-Type: application/json" -d $regBody | ConvertFrom-Json).id

$userToken = (curl.exe -s -X POST "$usersUrl/api/auth/login" -H "Content-Type: application/json" -d "{`"email`":`"$email`",`"password`":`"Senha@123`"}" | ConvertFrom-Json).token
Write-Host "      Jogador autenticado (ID: $userId)."

# 3. Criar Jogos no Catálogo (Admin)
Write-Host "[3/6] Criando jogos no catálogo como Admin (201 Created)..." -ForegroundColor Yellow
$gameBody = '{"title":"Cyber FIAP 2077","description":"RPG de acao","price":149.90}'
$gameId = (curl.exe -s -X POST "$catalogUrl/api/games" -H "Content-Type: application/json" -H "Authorization: Bearer $adminToken" -d $gameBody | ConvertFrom-Json).id
Write-Host "      Jogo criado com ID: $gameId"

# 4. Comprar Jogo
Write-Host "[4/6] Realizando compra do jogo (202 Accepted)..." -ForegroundColor Yellow
$purchaseBody = "{`"userId`":`"$userId`",`"gameId`":`"$gameId`"}"
$purchase = curl.exe -s -X POST "$catalogUrl/api/library/purchase" -H "Content-Type: application/json" -H "Authorization: Bearer $userToken" -d $purchaseBody | ConvertFrom-Json
Write-Host "      Pedido de compra enviado (Status: $($purchase.order.status))."

# 5. Rajada de consultas de sucesso (200 OK)
Write-Host "[5/6] Disparando rajada de consultas (200 OK)..." -ForegroundColor Yellow
1..20 | ForEach-Object {
    curl.exe -s "$catalogUrl/api/games" | Out-Null
    curl.exe -s "$catalogUrl/api/games/$gameId" | Out-Null
    curl.exe -s -H "Authorization: Bearer $userToken" "$catalogUrl/api/library/$userId" | Out-Null
    curl.exe -s "$usersUrl/health" | Out-Null
}
Write-Host "      20 requisicoes para cada endpoint enviadas."

# 6. Erros controlados para preencher as barras de 4xx no Grafana
Write-Host "[6/6] Provocando erros (400, 401, 404) para colorir os graficos..." -ForegroundColor Yellow
# 400 Bad Request
1..5 | ForEach-Object {
    curl.exe -s -X POST "$usersUrl/api/auth/register" -H "Content-Type: application/json" -d '{"email":"invalido"}' | Out-Null
}
# 401 Unauthorized
1..4 | ForEach-Object {
    curl.exe -s -X POST "$catalogUrl/api/games" -H "Content-Type: application/json" -d '{"title":"Sem Token"}' | Out-Null
}
# 404 Not Found
1..6 | ForEach-Object {
    curl.exe -s "$catalogUrl/api/games/00000000-0000-0000-0000-000000000000" | Out-Null
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host "  TESTES FINALIZADOS COM SUCESSO!        " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
