#Requires -Version 5.1
<#
.SYNOPSIS
    Executa todas as requisições HTTP das APIs FCG (Fase 2).

.DESCRIPTION
    Cobre health de Users, Catalog, Payments e Notifications, cadastro/login,
    CRUD de jogos (Admin), compra e consulta de biblioteca.

    Funciona com as APIs no Docker Compose, via kubectl port-forward ou
    rodando localmente - desde que as portas sejam as mesmas (5101-5104)
    ou sejam informadas por parâmetro.

.EXAMPLE
    # APIs já no ar (docker compose up  ou  port-forward)
    .\test-apis.ps1

.EXAMPLE
    # Sobe o compose e espera o /health antes de testar
    .\test-apis.ps1 -StartDocker

.EXAMPLE
    # Portas manuais
    .\test-apis.ps1 -UsersUrl http://localhost:5196 -CatalogUrl http://localhost:5200
#>
[CmdletBinding()]
param(
    [string]$UsersUrl = "http://localhost:5101",
    [string]$CatalogUrl = "http://localhost:5102",
    [string]$PaymentsUrl = "http://localhost:5103",
    [string]$NotificationsUrl = "http://localhost:5104",
    [string]$AdminEmail = "admin@fcg.com",
    [string]$AdminPassword = "AdminSenha@123",
    [string]$UserName = "Joao Silva",
    [string]$UserEmail = "",
    [string]$UserPassword = "Senha@123",
    [string]$CorrelationId = "demo-video-001",
    [int]$HealthTimeoutSeconds = 180,
    [int]$PurchaseWaitSeconds = 5,
    [switch]$StartDocker
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

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

# -----------------------------------------------------------------------------
# Opcional: subir Docker Compose
# -----------------------------------------------------------------------------
if ($StartDocker) {
    Write-Step "Subindo Docker Compose (docker compose up --build -d)"
    Push-Location $PSScriptRoot
    try {
        docker compose up --build -d
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose up falhou com codigo $LASTEXITCODE"
        }
    } finally {
        Pop-Location
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
Write-Host ("  User email    : {0}" -f $UserEmail)

Write-Step "[1/12] Health checks"
Wait-FcgHealth "UsersAPI" "$UsersUrl/health" $HealthTimeoutSeconds
Wait-FcgHealth "CatalogAPI" "$CatalogUrl/health" $HealthTimeoutSeconds
Wait-FcgHealth "PaymentsAPI" "$PaymentsUrl/health" $HealthTimeoutSeconds
Wait-FcgHealth "NotificationsAPI" "$NotificationsUrl/health" $HealthTimeoutSeconds

$null = Invoke-FcgRequest -Method GET -Url "$UsersUrl/health" -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/health" -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$PaymentsUrl/health" -Expected 200
$null = Invoke-FcgRequest -Method GET -Url "$NotificationsUrl/health" -Expected 200

# -----------------------------------------------------------------------------
# 2. Register
# -----------------------------------------------------------------------------
Write-Step "[2/12] POST /api/auth/register  (UsersAPI - publica UserCreatedEvent)"
$null = Invoke-FcgRequest -Method POST -Url "$UsersUrl/api/auth/register" -Expected 201 -Body @{
    name     = $UserName
    email    = $UserEmail
    password = $UserPassword
}

# -----------------------------------------------------------------------------
# 3. Login user
# -----------------------------------------------------------------------------
Write-Step "[3/12] POST /api/auth/login  (usuario comum)"
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
Write-Host ("    token  : {0}..." -f $userToken.Substring(0, [Math]::Min(40, $userToken.Length))) -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 4. Login admin
# -----------------------------------------------------------------------------
Write-Step "[4/12] POST /api/auth/login  (admin seed)"
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
Write-Step "[5/12] POST /api/games  (CatalogAPI - exige Admin)"
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
Write-Step "[6/12] GET /api/games?page=1&pageSize=10"
$null = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/api/games?page=1&pageSize=10" -Expected 200

# -----------------------------------------------------------------------------
# 7. Get game by id
# -----------------------------------------------------------------------------
Write-Step "[7/12] GET /api/games/{id}"
$null = Invoke-FcgRequest -Method GET -Url "$CatalogUrl/api/games/$gameId" -Expected 200

# -----------------------------------------------------------------------------
# 8. Update game
# -----------------------------------------------------------------------------
Write-Step "[8/12] PUT /api/games/{id}  (Admin)"
$null = Invoke-FcgRequest -Method PUT -Url "$CatalogUrl/api/games/$gameId" -Token $adminToken -Expected 200 -Body @{
    title       = "Cyber FIAP - Remasterizado"
    description = "Jogo demo atualizado para o video."
    price       = 79.90
}

# -----------------------------------------------------------------------------
# 9. Delete (jogo descartavel)
# -----------------------------------------------------------------------------
Write-Step "[9/12] POST + DELETE /api/games/{id}  (soft delete, Admin)"
$gameToDelete = Invoke-FcgRequest -Method POST -Url "$CatalogUrl/api/games" -Token $adminToken -Expected 201 -Body @{
    title       = "Jogo para Soft Delete"
    description = "Criado apenas para demonstrar o DELETE."
    price       = 19.90
}
$null = Invoke-FcgRequest -Method DELETE -Url "$CatalogUrl/api/games/$($gameToDelete.id)" -Token $adminToken -Expected 204

# -----------------------------------------------------------------------------
# 10. Purchase
# -----------------------------------------------------------------------------
Write-Step "[10/12] POST /api/library/purchase  (User - publica OrderPlacedEvent)"
$null = Invoke-FcgRequest -Method POST -Url "$CatalogUrl/api/library/purchase" -Token $userToken -Expected 202 -Body @{
    userId = $userId
    gameId = $gameId
}

# -----------------------------------------------------------------------------
# 11. Wait for events
# -----------------------------------------------------------------------------
Write-Step ("[11/12] Aguardando {0}s o fluxo RabbitMQ (Payments + Notifications + biblioteca)" -f $PurchaseWaitSeconds)
Start-Sleep -Seconds $PurchaseWaitSeconds

# -----------------------------------------------------------------------------
# 12. Library (retry)
# -----------------------------------------------------------------------------
Write-Step "[12/12] GET /api/library/{userId}"
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
Write-Host "    docker compose -f `"$PSScriptRoot\docker-compose.yml`" logs --tail=50 notifications-api"
Write-Host "    docker compose -f `"$PSScriptRoot\docker-compose.yml`" logs | Select-String $CorrelationId"
Write-Host ""
Write-Host "  Logs dos eventos (Kubernetes):"
Write-Host "    kubectl logs deployment/payments-api --tail=50"
Write-Host "    kubectl logs deployment/notifications-api --tail=50"
Write-Host "=============================================" -ForegroundColor Yellow

if ($script:Failed -gt 0) { exit 1 }
exit 0
