# Applies database/identity/migrations/*.sql in order against the Docker Postgres container.
# Requires: Docker Desktop running.

param(
  [switch]$Reset
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Container = "nexa-identity-db"
$PgUser = "nexa_identity"
$PgDb = "nexa_identity"
$ComposeFile = Join-Path $Root "docker-compose.yml"

function Wait-Database {
  $attempts = 0
  while ($attempts -lt 30) {
    $ready = docker exec $Container pg_isready -U $PgUser -d $PgDb 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 2
    $attempts++
  }
  throw "Postgres did not become ready in time."
}

function Invoke-PsqlFile {
  param([string]$Path)
  Get-Content -Raw -Encoding UTF8 $Path | docker exec -i $Container psql -v ON_ERROR_STOP=1 -U $PgUser -d $PgDb
  if ($LASTEXITCODE -ne 0) {
    throw "Migration failed: $Path"
  }
}

function Test-MigrationApplied {
  param([string]$Filename)
  $tableExists = docker exec $Container psql -U $PgUser -d $PgDb -tAc "SELECT to_regclass('public.schema_migrations');" 2>$null
  if ($tableExists -notmatch "schema_migrations") { return $false }
  $sql = "SELECT 1 FROM schema_migrations WHERE filename = '$Filename' LIMIT 1;"
  $result = docker exec $Container psql -U $PgUser -d $PgDb -tAc $sql 2>$null
  return ($result -match "1")
}

function Register-Migration {
  param([string]$Filename)
  $sql = "INSERT INTO schema_migrations (filename) VALUES ('$Filename') ON CONFLICT DO NOTHING;"
  docker exec $Container psql -U $PgUser -d $PgDb -c $sql | Out-Null
}

Write-Host "Starting Nexa Identity database container..."
Set-Location $Root
docker compose -f $ComposeFile up -d

if ($Reset) {
  Write-Host "Resetting database volume..."
  docker compose -f $ComposeFile down -v
  docker compose -f $ComposeFile up -d
}

Wait-Database
Write-Host "Database is ready."

$migrations = Get-ChildItem (Join-Path $Root "migrations\*.sql") | Sort-Object Name
$applied = 0
$skipped = 0

foreach ($file in $migrations) {
  $name = $file.Name
  if ($name -eq "000_bootstrap.sql") {
    if (-not (Test-MigrationApplied $name)) {
      Write-Host "Applying $name ..."
      Invoke-PsqlFile $file.FullName
      Register-Migration $name
      $applied++
    } else {
      Write-Host "Skip $name (already applied)"
      $skipped++
    }
    continue
  }

  if (-not (Test-MigrationApplied "000_bootstrap.sql")) {
    throw "000_bootstrap.sql must run before other migrations."
  }

  if (Test-MigrationApplied $name) {
    Write-Host "Skip $name (already applied)"
    $skipped++
    continue
  }

  Write-Host "Applying $name ..."
  Invoke-PsqlFile $file.FullName
  Register-Migration $name
  $applied++
}

Write-Host ""
Write-Host "Done. Applied: $applied, skipped: $skipped"
Write-Host "Connect: postgresql://nexa_identity:nexa_identity_dev@localhost:5433/nexa_identity"
Write-Host "Backend: cd backend\identity && npm start"
