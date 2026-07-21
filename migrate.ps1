# Starts the unified database stack and applies identity + stays migrations.
# Requires: Docker Desktop running.
#
# Stack: identity-db (:5433), stays-db (:5434), redis (:6379)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$ComposeFile = Join-Path $Root "docker-compose.yml"

Write-Host "Starting unified database stack (identity, stays, redis)..."
Set-Location $Root
docker compose -f $ComposeFile up -d

Write-Host ""
Write-Host "=== Identity migrations ==="
& (Join-Path $Root "identity\migrate.ps1") -ComposeFile $ComposeFile

Write-Host ""
Write-Host "=== Stays migrations ==="
& (Join-Path $Root "stays\migrate.ps1") -ComposeFile $ComposeFile

Write-Host ""
Write-Host "All migrations complete."
