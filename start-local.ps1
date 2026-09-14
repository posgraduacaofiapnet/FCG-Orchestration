#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$lambdaProject = Join-Path $PSScriptRoot "..\FCG-Notifications-Lambda\src\FCG.Notifications.Function\FCG.Notifications.Function.csproj"
$artifactRoot = Join-Path $PSScriptRoot ".artifacts"
$publishDirectory = Join-Path $artifactRoot "lambda-publish"
$lambdaArchive = Join-Path $artifactRoot "fcg-notifications.zip"

if (-not $SkipBuild) {
    if (Test-Path -LiteralPath $publishDirectory) {
        Remove-Item -LiteralPath $publishDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null
    dotnet restore $lambdaProject --source https://api.nuget.org/v3/index.json
    if ($LASTEXITCODE -ne 0) { throw "Falha ao restaurar a Lambda." }
    dotnet publish $lambdaProject -c Release -o $publishDirectory --no-restore
    if ($LASTEXITCODE -ne 0) { throw "Falha ao publicar a Lambda." }

    if (Test-Path -LiteralPath $lambdaArchive) {
        Remove-Item -LiteralPath $lambdaArchive -Force
    }
    Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $lambdaArchive -CompressionLevel Optimal
}

if (-not (Test-Path -LiteralPath $lambdaArchive)) {
    throw "Pacote da Lambda nao encontrado em $lambdaArchive. Execute sem -SkipBuild."
}

Push-Location $PSScriptRoot
try {
    # LocalStack keeps the Lambda package in memory. Recreating the stack makes
    # every execution deterministic and guarantees that the freshly built ZIP
    # is the code exercised by the end-to-end test.
    docker compose up --build --force-recreate -d
    if ($LASTEXITCODE -ne 0) { throw "docker compose up falhou." }
}
finally {
    Pop-Location
}
