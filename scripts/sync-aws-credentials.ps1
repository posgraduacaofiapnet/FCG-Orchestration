#Requires -Version 5.1
<#
.SYNOPSIS
    Publica as credenciais AWS locais no Secrets Manager e no Kubernetes.

.DESCRIPTION
    Le o profile do AWS CLI (~/.aws/credentials), opcionalmente grava o JSON
    no Secrets Manager (fcg/catalog-aws) e cria o Secret catalog-aws-credentials
    no cluster. Nao imprime a secret key.

.EXAMPLE
    aws configure
    .\scripts\sync-aws-credentials.ps1

.EXAMPLE
    .\scripts\sync-aws-credentials.ps1 -SkipSecretsManager
#>
[CmdletBinding()]
param(
    [string]$SecretName = "fcg/catalog-aws",
    [string]$KubernetesSecretName = "catalog-aws-credentials",
    [string]$Region = "us-east-1",
    [switch]$SkipSecretsManager,
    [switch]$SkipKubernetes
)

$ErrorActionPreference = "Stop"

function Get-RequiredCommand {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando '$Name' nao encontrado. Instale AWS CLI v2 e/ou kubectl."
    }
}

Get-RequiredCommand aws

$accessKey = (aws configure get aws_access_key_id).Trim()
$secretKey = (aws configure get aws_secret_access_key).Trim()
$configuredRegion = (aws configure get region)
if (-not [string]::IsNullOrWhiteSpace($configuredRegion)) {
    $Region = $configuredRegion.Trim()
}

if ([string]::IsNullOrWhiteSpace($accessKey) -or [string]::IsNullOrWhiteSpace($secretKey)) {
    throw "AWS CLI sem credenciais. Rode: aws configure"
}

$secretJson = @{
    AWS_ACCESS_KEY_ID     = $accessKey
    AWS_SECRET_ACCESS_KEY = $secretKey
    AWS_REGION            = $Region
} | ConvertTo-Json -Compress

if (-not $SkipSecretsManager) {
    Write-Host ">>> Secrets Manager: $SecretName ($Region)"
    $exists = $false
    try {
        aws secretsmanager describe-secret --secret-id $SecretName --region $Region | Out-Null
        if ($LASTEXITCODE -eq 0) { $exists = $true }
    } catch {
        $exists = $false
    }

    $tempFile = Join-Path $env:TEMP "fcg-catalog-aws.json"
    try {
        [System.IO.File]::WriteAllText($tempFile, $secretJson)
        if ($exists) {
            aws secretsmanager put-secret-value --secret-id $SecretName --secret-string "file://$tempFile" --region $Region | Out-Null
            Write-Host "    Secret atualizado."
        } else {
            aws secretsmanager create-secret --name $SecretName --secret-string "file://$tempFile" --region $Region | Out-Null
            Write-Host "    Secret criado."
        }
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

if (-not $SkipKubernetes) {
    Get-RequiredCommand kubectl
    Write-Host ">>> Kubernetes Secret: $KubernetesSecretName"
    kubectl create secret generic $KubernetesSecretName `
        --from-literal=AWS_ACCESS_KEY_ID=$accessKey `
        --from-literal=AWS_SECRET_ACCESS_KEY=$secretKey `
        --from-literal=AWS_REGION=$Region `
        --dry-run=client -o yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao aplicar o Secret $KubernetesSecretName"
    }
    Write-Host "    Secret aplicado. Reinicie o pod se ele ja estava no ar:"
    Write-Host "    kubectl rollout restart deployment/catalog-api"
}

Write-Host ">>> Pronto. A CatalogAPI usa a cadeia padrao do AWS SDK (arquivo ~/.aws no Docker, Secret no Kubernetes)."
