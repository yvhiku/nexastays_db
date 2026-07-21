# Applies database/stays/migrations/*.sql in order against the Docker Postgres container.
# Requires: Docker Desktop running.
#
# By default uses the unified stack at database/docker-compose.yml (stays-db on :5434).
# Pass -ComposeFile to override, or set NEXA_DATABASE_COMPOSE.

param(
  [switch]$Reset,
  [string]$ComposeFile = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$ServiceName = "stays-db"
$PgUser = "nexa_stays"
$PgDb = "nexa_stays"

if (-not $ComposeFile) {
  if ($env:NEXA_DATABASE_COMPOSE) {
    $ComposeFile = $env:NEXA_DATABASE_COMPOSE
  } else {
    $UnifiedCompose = Join-Path (Split-Path $Root -Parent) "docker-compose.yml"
    if (Test-Path $UnifiedCompose) {
      $ComposeFile = $UnifiedCompose
    } else {
      $ComposeFile = Join-Path $Root "docker-compose.yml"
    }
  }
}

$ComposeDir = Split-Path $ComposeFile -Parent
$UnifiedCompose = Join-Path (Split-Path $Root -Parent) "docker-compose.yml"
$UsingUnified = (Test-Path $UnifiedCompose) -and ((Resolve-Path $ComposeFile).Path -eq (Resolve-Path $UnifiedCompose).Path)

function Wait-Database {
  $attempts = 0
  while ($attempts -lt 30) {
    docker compose -f $ComposeFile exec -T $ServiceName pg_isready -U $PgUser -d $PgDb 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 2
    $attempts++
  }
  throw "Postgres did not become ready in time."
}

function Invoke-PsqlFile {
  param([string]$Path)
  Get-Content -Raw -Encoding UTF8 $Path | docker compose -f $ComposeFile exec -T $ServiceName psql -v ON_ERROR_STOP=1 -U $PgUser -d $PgDb
  if ($LASTEXITCODE -ne 0) {
    throw "Migration failed: $Path"
  }
}

function Test-MigrationApplied {
  param([string]$Filename)
  $tableExists = docker compose -f $ComposeFile exec -T $ServiceName psql -U $PgUser -d $PgDb -tAc "SELECT to_regclass('public.schema_migrations');" 2>$null
  if ($tableExists -notmatch "schema_migrations") { return $false }
  $sql = "SELECT 1 FROM schema_migrations WHERE filename = '$Filename' LIMIT 1;"
  $result = docker compose -f $ComposeFile exec -T $ServiceName psql -U $PgUser -d $PgDb -tAc $sql 2>$null
  return ($result -match "1")
}

function Register-Migration {
  param([string]$Filename)
  $sql = "INSERT INTO schema_migrations (filename) VALUES ('$Filename') ON CONFLICT DO NOTHING;"
  docker compose -f $ComposeFile exec -T $ServiceName psql -U $PgUser -d $PgDb -c $sql | Out-Null
}

if ($UsingUnified) {
  Write-Host "Using unified database stack (stays-db on :5434)..."
} else {
  Write-Host "Starting Nexa Stays database container..."
}

Set-Location $ComposeDir
docker compose -f $ComposeFile up -d $ServiceName

if ($Reset) {
  if ($UsingUnified) {
    Write-Warning "Reset with the unified stack removes identity, stays, and redis volumes."
  }
  Write-Host "Resetting database volume..."
  docker compose -f $ComposeFile down -v
  docker compose -f $ComposeFile up -d $ServiceName
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
Write-Host "Connect: postgresql://nexa_stays:nexa_stays_dev@localhost:5434/nexa_stays"
Write-Host "Backend: cd backend\stays && npm run start:dev"
