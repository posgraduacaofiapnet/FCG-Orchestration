#Requires -Version 5.1
<#
.SYNOPSIS
    Executa as requisições HTTP do fluxo FCG da Fase 3.

.DESCRIPTION
    Cobre health de Users, Catalog, Payments e dos workers de outbox, cadastro/login,
    CRUD de jogos (Admin), compra e consulta de biblioteca.

    UsersAPI e CatalogAPI passam pelo Kong em http://localhost:8000
    (Docker Compose ou kubectl port-forward). Payments e os workers
    continuam nas portas diretas (5103/5104/5105).

.EXAMPLE
    # APIs já no ar (docker compose up  ou  port-forward do Kong)
    .\test-apis.ps1

.EXAMPLE
    # Sobe o compose e espera o health antes de testar
    .\test-apis.ps1 -StartDocker

.EXAMPLE
    # Sem Kong: APIs diretas
    .\test-apis.ps1 -GatewayUrl "" -UsersUrl http://localhost:5101 -CatalogUrl http://localhost:5102 -UsersHealthUrl http://localhost:5101/health -CatalogHealthUrl http://localhost:5102/health
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "http://localhost:8000",
    [string]$UsersUrl = "",
    [string]$CatalogUrl = "",
    [string]$UsersHealthUrl = "",
    [string]$CatalogHealthUrl = "",
    [string]$PaymentsUrl = "http://localhost:5103",
    [string]$UsersOutboxUrl = "http://localhost:5104",
    [string]$CatalogOutboxUrl = "http://localhost:5105",
    [string]$AdminEmail = "admin@fcg.com",
    [string]$AdminPassword = "AdminSenha@123",
    [string]$UserName = "Joao Silva",
    [string]$UserEmail = "",
    [string]$UserPassword = "Senha@123",
    [string]$CorrelationId = "demo-video-001",
    [int]$HealthTimeoutSeconds = 180,
    [int]$PurchaseWaitSeconds = 5,
    [int]$AsyncTimeoutSeconds = 120,
    [switch]$StartDocker
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($UsersUrl)) { $UsersUrl = $GatewayUrl }
if ([string]::IsNullOrWhiteSpace($CatalogUrl)) { $CatalogUrl = $GatewayUrl }
if ([string]::IsNullOrWhiteSpace($UsersHealthUrl)) { $UsersHealthUrl = "$GatewayUrl/health/users" }
if ([string]::IsNullOrWhiteSpace($CatalogHealthUrl)) { $CatalogHealthUrl = "$GatewayUrl/health/catalog" }

if ([string]::IsNullOrWhiteSpace($UserEmail)) {
    $UserEmail = "tester-{0}@fcg.com" -f (Get-Date -Format "yyyyMMddHHmmss")
}

$script:CorrelationId = $CorrelationId
$script:Failed = 0
$script:Passed = 0

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Write-Result {
    param(
        [bool]$Ok,
        [int]$Status,
        [string]$Method,
        [string]$Url,
        $Body
    )

    $icon = if ($Ok) { "OK" } else { "FAIL" }
    $color = if ($Ok) { "Green" } else { "Red" }
    if ($Ok) { $script:Passed++ } else { $script:Failed++ }

    Write-Host ("    [{0}] {1} {2}  ->  {3}" -f $icon, $Method, $Url, $Status) -ForegroundColor $color
    if ($null -ne $Body -and $Body -ne "") {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 8 }
        $json = $json -replace '"token"\s*:\s*"[^"]+"', '"token": "<redacted>"'
        foreach ($line in ($json -split "`r?`n")) {
            Write-Host "        $line"
        }
    }
}

function ConvertFrom-JsonSafe {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    try { return ($Raw | ConvertFrom-Json) } catch { return $Raw }
}

function Read-ErrorBody {
    param($Response)
    if ($null -eq $Response) { return "" }

    try {
        $stream = $Response.GetResponseStream()
        if ($null -eq $stream) { return "" }
        $reader = New-Object System.IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } catch {
        return ""
    }
}

function Invoke-FcgRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        $Body,
        [string]$Token,
        [int[]]$Expected = @(200)
    )

    $headers = @{
        "X-Correlation-ID" = $script:CorrelationId
        "Accept"           = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method          = $Method
        Uri             = $Url
        Headers         = $headers
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = ($Body | ConvertTo-Json -Compress -Depth 8)
    }

    $status = 0
    $raw = ""

    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $response = Invoke-WebRequest @params -SkipHttpErrorCheck
            $status = [int]$response.StatusCode
            $raw = [string]$response.Content
        } else {
            $response = Invoke-WebRequest @params
            $status = [int]$response.StatusCode
            $raw = [string]$response.Content
        }
    } catch {
        $httpResponse = $_.Exception.Response
        if ($httpResponse) {
            $status = [int]$httpResponse.StatusCode
            $raw = Read-ErrorBody $httpResponse
        } else {
            Write-Result -Ok:$false -Status 0 -Method $Method -Url $Url -Body $_.Exception.Message
            throw
        }
    }

    $parsed = ConvertFrom-JsonSafe $raw
    $ok = $Expected -contains $status
    Write-Result -Ok:$ok -Status $status -Method $Method -Url $Url -Body $parsed

    if (-not $ok) {
        throw "Status $status fora do esperado ($($Expected -join ', ')) em $Method $Url"
    }

    return $parsed
}

function Wait-FcgHealth {
    param(
        [string]$Name,
        [string]$Url,
        [int]$TimeoutSeconds
    )

    Write-Host ("    Aguardando {0} em {1} ..." -f $Name, $Url) -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null

    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 5
            Write-Host ("    {0} pronto." -f $Name) -ForegroundColor Green
            return
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 3
        }
    }

    throw "$Name nao respondeu em $TimeoutSeconds s. Ultimo erro: $lastError"
}

function Invoke-LocalAws {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & docker exec fcg_localstack awslocal @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no LocalStack: $($output -join [Environment]::NewLine)"
    }

    return ($output -join [Environment]::NewLine)
}

function Get-CompletedNotificationCount {
    $raw = Invoke-LocalAws -Arguments @(
        "dynamodb", "scan",
        "--table-name", "fcg-notification-idempotency",
        "--output", "json"
    )
    $scan = $raw | ConvertFrom-Json
    return @($scan.Items | Where-Object { $_.Status.S -eq "Completed" }).Count
}

function Get-NotificationQueueState {
    $raw = Invoke-LocalAws -Arguments @(
        "sqs", "get-queue-attributes",
        "--queue-url", "http://localstack:4566/queue/us-east-1/000000000000/fcg-notifications-queue",
        "--attribute-names", "ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible",
        "--output", "json"
    )
    return ($raw | ConvertFrom-Json).Attributes
}

function Invoke-SqlScalar {
    param([Parameter(Mandatory)][string]$Query)

    $output = $Query | & docker exec -i fcg_sqlserver bash -lc '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -h -1 -W' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao consultar SQL Server: $($output -join [Environment]::NewLine)"
    }

    $value = ($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1).Trim()
    return [int]$value
}

# -----------------------------------------------------------------------------
# Opcional: subir Docker Compose
# -----------------------------------------------------------------------------
if ($StartDocker) {
    Write-Step "Empacotando Lambda e subindo o ambiente local completo"
    & (Join-Path $PSScriptRoot "start-local.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "start-local.ps1 falhou com codigo $LASTEXITCODE"
    }
}

# -----------------------------------------------------------------------------
# 1. Health
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host "  FCG - FIAP Cloud Games - Teste das APIs" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ("  CorrelationId : {0}" -f $CorrelationId)
Write-Host ("  Gateway       : {0}" -f $GatewayUrl)
Write-Host ("  User email    : {0}" -f $UserEmail)

Write-Step "[1/13] Health checks"
Wait-FcgHealth "UsersAPI" $UsersHealthUrl $HealthTimeoutSeconds
Wait-FcgHealth "CatalogAPI" $CatalogHealthUrl $HealthTimeoutSeconds
Wait-FcgHealth "PaymentsAPI" "$PaymentsUrl/health" $HealthTimeoutSeconds
Wait-FcgHealth "Users Outbox Processor" "$UsersOutboxUrl/health/ready" $HealthTimeoutSeconds
Wait-FcgHealth "Catalog Outbox Processor" "$CatalogOutboxUrl/health/ready" $HealthTimeoutSeconds
Wait-FcgHealth "LocalStack" "http://localhost:4566/_localstack/health" $HealthTimeoutSeconds

$null = Invoke-FcgRequest -Method GET -Url $UsersHealthUrl -Expected 200
$null = Invoke-FcgRequest -Method GET -Url $CatalogHealthUrl -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$PaymentsUrl/health" -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$UsersOutboxUrl/health/ready" -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$CatalogOutboxUrl/health/ready" -Expected 200
$initialCompletedNotifications = Get-CompletedNotificationCount

# -----------------------------------------------------------------------------
# 2. Register
# -----------------------------------------------------------------------------
Write-Step "[2/13] POST /api/auth/register  (UsersAPI - persiste UserCreated no outbox)"
$null = Invoke-FcgRequest -Method POST -Url "$UsersUrl/api/auth/register" -Expected 201 -Body @{
    name     = $UserName
    email    = $UserEmail
    password = $UserPassword
}

# -----------------------------------------------------------------------------
# 3. Login user
# -----------------------------------------------------------------------------
Write-Step "[3/13] POST /api/auth/login  (usuario comum)"
$loginUser = Invoke-FcgRequest -Method POST -Url "$UsersUrl/api/auth/login" -Expected 200 -Body @{
    email    = $UserEmail
    password = $UserPassword
}
$userToken = [string]$loginUser.token
$userId = [string]$loginUser.userId
if ([string]::IsNullOrWhiteSpace($userToken) -or [string]::IsNullOrWhiteSpace($userId)) {
    throw "Login do usuario nao retornou token/userId."
}
Write-Host ("    userId : {0}" -f $userId) -ForegroundColor DarkGray
Write-Host "    token  : obtido (conteudo ocultado)" -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 4. Login admin
# -----------------------------------------------------------------------------
Write-Step "[4/13] POST /api/auth/login  (admin seed)"
$loginAdmin = Invoke-FcgRequest -Method POST -Url "$UsersUrl/api/auth/login" -Expected 200 -Body @{
    email    = $AdminEmail
    password = $AdminPassword
}
$adminToken = [string]$loginAdmin.token
if ([string]::IsNullOrWhiteSpace($adminToken)) {
    throw "Login do admin nao retornou token. Confirme o seed Admin__Email / Admin__Password."
}

# -----------------------------------------------------------------------------
# 5. Create game
# -----------------------------------------------------------------------------
Write-Step "[5/13] POST /api/games  (CatalogAPI - exige Admin)"
$game = Invoke-FcgRequest -Method POST -Url "$CatalogUrl/api/games" -Token $adminToken -Expected 201 -Body @{
    title       = "Cyber FIAP"
    description = "Jogo demo para o fluxo de compra."
    price       = 99.90
}
$gameId = [string]$game.id
if ([string]::IsNullOrWhiteSpace($gameId)) {
    throw "Criacao do jogo nao retornou id."
}
Write-Host ("    gameId : {0}" -f $gameId) -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 6. List games
# -----------------------------------------------------------------------------
Write-Step "[6/13] GET /api/games?page=1&pageSize=10"
$null = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/api/games?page=1&pageSize=10" -Expected 200

# -----------------------------------------------------------------------------
# 7. Get game by id
# -----------------------------------------------------------------------------
Write-Step "[7/13] GET /api/games/{id}"
$null = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/api/games/$gameId" -Expected 200

# -----------------------------------------------------------------------------
# 8. Update game
# -----------------------------------------------------------------------------
Write-Step "[8/13] PUT /api/games/{id}  (Admin)"
$null = Invoke-FcgRequest -Method PUT -Url "$CatalogUrl/api/games/$gameId" -Token $adminToken -Expected 200 -Body @{
    title       = "Cyber FIAP - Remasterizado"
    description = "Jogo demo atualizado para o video."
    price       = 79.90
}

# -----------------------------------------------------------------------------
# 9. Delete (jogo descartavel)
# -----------------------------------------------------------------------------
Write-Step "[9/13] POST + DELETE /api/games/{id}  (soft delete, Admin)"
$gameToDelete = Invoke-FcgRequest -Method POST -Url "$CatalogUrl/api/games" -Token $adminToken -Expected 201 -Body @{
    title       = "Jogo para Soft Delete"
    description = "Criado apenas para demonstrar o DELETE."
    price       = 19.90
}
$null = Invoke-FcgRequest -Method DELETE -Url "$CatalogUrl/api/games/$($gameToDelete.id)" -Token $adminToken -Expected 204

# -----------------------------------------------------------------------------
# 10. Purchase
# -----------------------------------------------------------------------------
Write-Step "[10/13] POST /api/library/purchase  (User - publica OrderPlacedEvent)"
$null = Invoke-FcgRequest -Method POST -Url "$CatalogUrl/api/library/purchase" -Token $userToken -Expected 202 -Body @{
    userId = $userId
    gameId = $gameId
}

# -----------------------------------------------------------------------------
# 11. Wait for events
# -----------------------------------------------------------------------------
Write-Step ("[11/13] Aguardando {0}s o fluxo RabbitMQ, outbox e biblioteca" -f $PurchaseWaitSeconds)
Start-Sleep -Seconds $PurchaseWaitSeconds

# -----------------------------------------------------------------------------
# 12. Library (retry)
# -----------------------------------------------------------------------------
Write-Step "[12/13] GET /api/library/{userId}"
$library = $null
$attempts = 6
for ($i = 1; $i -le $attempts; $i++) {
    $library = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/api/library/$userId" -Token $userToken -Expected 200
    $count = 0
    if ($library -is [System.Array]) { $count = $library.Length }
    elseif ($library) { $count = @($library).Count }

    if ($count -gt 0) { break }
    if ($i -lt $attempts) {
        Write-Host "    Biblioteca ainda vazia (pagamento assincrono). Nova tentativa em 2s..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 2
    }
}

if ($count -eq 0) {
    throw "A biblioteca permaneceu vazia depois de $attempts tentativas."
}

# -----------------------------------------------------------------------------
# 13. Transactional outbox -> SQS -> Lambda -> DynamoDB
# -----------------------------------------------------------------------------
Write-Step "[13/13] Validando Outbox -> SQS -> Lambda -> DynamoDB"
$expectedCompletedNotifications = $initialCompletedNotifications + 3
$asyncDeadline = (Get-Date).AddSeconds($AsyncTimeoutSeconds)
$completedNotifications = 0
$usersOutboxSuccess = 0
$catalogOutboxSuccess = 0
$visibleMessages = -1
$inFlightMessages = -1
$asyncComplete = $false

do {
    $completedNotifications = Get-CompletedNotificationCount
    $queueState = Get-NotificationQueueState
    $visibleMessages = [int]$queueState.ApproximateNumberOfMessages
    $inFlightMessages = [int]$queueState.ApproximateNumberOfMessagesNotVisible

    $usersOutboxSuccess = Invoke-SqlScalar "SET NOCOUNT ON; SELECT COUNT(*) FROM FCGUsersDb.dbo.OutboxMessages WHERE EventType = 'UserCreated' AND IsSuccessful = 1 AND Attempts = 1 AND JSON_VALUE(Payload, '$.userId') = '$userId';"
    $catalogOutboxSuccess = Invoke-SqlScalar "SET NOCOUNT ON; SELECT COUNT(*) FROM FCGCatalogDb.dbo.OutboxMessages WHERE EventType IN ('OrderPlaced', 'PaymentProcessed') AND IsSuccessful = 1 AND Attempts = 1 AND JSON_VALUE(Payload, '$.userId') = '$userId';"

    $asyncComplete = (
        $completedNotifications -ge $expectedCompletedNotifications -and
        $usersOutboxSuccess -eq 1 -and
        $catalogOutboxSuccess -eq 2 -and
        $visibleMessages -eq 0 -and
        $inFlightMessages -eq 0
    )

    if (-not $asyncComplete) { Start-Sleep -Seconds 2 }
} while (-not $asyncComplete -and (Get-Date) -lt $asyncDeadline)

if (-not $asyncComplete) {
    throw "Fluxo assincrono incompleto. Dynamo Completed=$completedNotifications/$expectedCompletedNotifications; Users Outbox=$usersOutboxSuccess/1; Catalog Outbox=$catalogOutboxSuccess/2; SQS visible=$visibleMessages; SQS in-flight=$inFlightMessages."
}

$script:Passed++
Write-Host "    [OK] 3 outboxes enviados na primeira tentativa, 3 eventos processados e fila vazia." -ForegroundColor Green

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ("  Concluidos : {0}  |  Falhas : {1}" -f $script:Passed, $script:Failed) -ForegroundColor $(if ($script:Failed -eq 0) { "Green" } else { "Red" })
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ("  User ID : {0}" -f $userId)
Write-Host ("  Game ID : {0}" -f $gameId)
Write-Host ("  Email   : {0}" -f $UserEmail)
Write-Host ""
Write-Host "  Logs dos eventos (Docker):"
Write-Host "    docker compose -f `"$PSScriptRoot\docker-compose.yml`" logs --tail=50 payments-api"
Write-Host "    docker compose -f `"$PSScriptRoot\docker-compose.yml`" logs --tail=50 users-outbox-processor catalog-outbox-processor"
Write-Host "    docker compose -f `"$PSScriptRoot\docker-compose.yml`" logs | Select-String $CorrelationId"
Write-Host ""
Write-Host "  Logs dos eventos (Kubernetes):"
Write-Host "    kubectl logs deployment/payments-api --tail=50"
Write-Host "    kubectl logs deployment/users-outbox-processor --tail=50"
Write-Host "    kubectl logs deployment/catalog-outbox-processor --tail=50"
Write-Host "=============================================" -ForegroundColor Yellow

if ($script:Failed -gt 0) { exit 1 }
exit 0
