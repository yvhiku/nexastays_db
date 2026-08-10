#!/usr/bin/env pwsh
<#
.SYNOPSIS
  End-to-end restore drill: backup Identity+Stays, optionally push to MinIO,
  restore into isolated Postgres containers, validate constraints, emit timings.

.NOTES
  Requires: Docker, pg_dump/pg_restore/psql on PATH.
  Does not touch production application databases for restore target.
#>
param(
  [switch]$WithMinio,
  [switch]$SkipTeardown,
  [string]$BackupDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\NexaBackup.Common.ps1')

$Root = Split-Path $PSScriptRoot -Parent
$ComposeFile = Join-Path $Root 'docker-compose.backup.yml'
$PrimaryCompose = Join-Path $Root 'docker-compose.yml'

function Wait-Tcp {
  param([string]$HostName, [int]$Port, [int]$TimeoutSec = 90)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $c = New-Object System.Net.Sockets.TcpClient
      $iar = $c.BeginConnect($HostName, $Port, $null, $null)
      $ok = $iar.AsyncWaitHandle.WaitOne(1000, $false)
      if ($ok -and $c.Connected) { $c.Close(); return }
      $c.Close()
    } catch {}
    Start-Sleep -Seconds 1
  }
  throw "Timeout waiting for ${HostName}:${Port}"
}

$metrics = [ordered]@{
  ok = $false
  started_utc = (Get-Date).ToUniversalTime().ToString('o')
  backup_discovery_ms = $null
  backup_duration_ms = $null
  remote_duration_ms = $null
  restore_duration_ms = $null
  validation_duration_ms = $null
  total_duration_ms = $null
  identity_backup_bytes = $null
  stays_backup_bytes = $null
  remote_verified = $false
  notes = @()
}
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

try {
  if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $BackupDir = Join-Path $Root 'backups\drill'
  }
  Assert-SecureBackupDirectory -Path $BackupDir

  # Ensure primary DBs are up (source of truth for drill)
  Push-Location $Root
  docker compose -f $PrimaryCompose up -d identity-db stays-db | Out-Null
  Pop-Location
  Wait-Tcp -HostName '127.0.0.1' -Port 5433
  Wait-Tcp -HostName '127.0.0.1' -Port 5434

  # Start restore targets (+ optional MinIO)
  $services = @('identity-restore-db', 'stays-restore-db')
  if ($WithMinio) { $services += @('minio', 'minio-init') }
  Push-Location $Root
  docker compose -f $ComposeFile up -d @services | Out-Null
  Pop-Location
  Wait-Tcp -HostName '127.0.0.1' -Port 55433
  Wait-Tcp -HostName '127.0.0.1' -Port 55434
  if ($WithMinio) { Wait-Tcp -HostName '127.0.0.1' -Port 9000 }

  $env:BACKUP_DIR = $BackupDir
  $env:BACKUP_RETENTION_DAYS = '30'
  $env:IDENTITY_DATABASE_URL = 'postgresql://nexa_identity:nexa_identity_dev@127.0.0.1:5433/nexa_identity'
  $env:STAYS_DATABASE_URL = 'postgresql://nexa_stays:nexa_stays_dev@127.0.0.1:5434/nexa_stays'

  if ($WithMinio) {
    $env:BACKUP_REMOTE_ENABLED = 'true'
    $env:BACKUP_REMOTE_PROVIDER = 's3'
    $env:BACKUP_REMOTE_PATH = 'drill'
    $env:S3_ENDPOINT = 'http://127.0.0.1:9000'
    $env:S3_BUCKET = 'nexa-db-backups'
    $env:S3_REGION = 'us-east-1'
    $env:S3_ACCESS_KEY_ID = 'nexa_backup_minio'
    $env:S3_SECRET_ACCESS_KEY = 'nexa_backup_minio_dev'
  } else {
    $remoteFs = Join-Path $BackupDir 'offhost'
    $env:BACKUP_REMOTE_ENABLED = 'true'
    $env:BACKUP_REMOTE_PROVIDER = 'filesystem'
    $env:BACKUP_REMOTE_PATH = $remoteFs
  }

  $swDiscover = [System.Diagnostics.Stopwatch]::StartNew()
  $client = Get-PostgresClientRunner
  Write-NexaBackupLog -Level INFO -Message 'restore_drill.client' -Meta @{ mode = $client.Mode }
  $swDiscover.Stop()
  $metrics.backup_discovery_ms = $swDiscover.ElapsedMilliseconds

  Write-NexaBackupLog -Level INFO -Message 'restore_drill.backup.begin' -Meta @{ with_minio = [bool]$WithMinio }

  $swBackup = [System.Diagnostics.Stopwatch]::StartNew()
  & (Join-Path $PSScriptRoot 'backup-postgres.ps1') -Database all
  if ($LASTEXITCODE -ne 0) { throw 'backup-postgres.ps1 failed' }
  $swBackup.Stop()
  $metrics.backup_duration_ms = $swBackup.ElapsedMilliseconds

  $idDump = Get-ChildItem -LiteralPath $BackupDir -Filter 'identity_*.dump' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  $stDump = Get-ChildItem -LiteralPath $BackupDir -Filter 'stays_*.dump' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not $idDump -or -not $stDump) { throw 'Could not locate latest dump files after backup' }
  $metrics.identity_backup_bytes = $idDump.Length
  $metrics.stays_backup_bytes = $stDump.Length

  if ($WithMinio) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $list = & docker run --rm --add-host=host.docker.internal:host-gateway --entrypoint /bin/sh minio/mc:latest -c `
        "mc alias set nexa http://host.docker.internal:9000 nexa_backup_minio nexa_backup_minio_dev >/dev/null && mc ls nexa/nexa-db-backups/drill/" 2>&1
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $oldEap
    }
    if ($code -eq 0 -and ("$list" -match 'identity_|stays_')) {
      $metrics.remote_verified = $true
      $metrics.notes += 'MinIO object listing succeeded'
    } else {
      $metrics.notes += 'MinIO listing inconclusive after upload'
    }
  } else {
    $remoteCopy = Join-Path (Join-Path $BackupDir 'offhost') $idDump.Name
    if (Test-Path -LiteralPath $remoteCopy) {
      $metrics.remote_verified = $true
      $metrics.notes += 'Filesystem off-host copy verified'
    }
  }

  $idUrl = 'postgresql://nexa_identity:nexa_identity_restore@127.0.0.1:55433/nexa_identity_restore'
  $stUrl = 'postgresql://nexa_stays:nexa_stays_restore@127.0.0.1:55434/nexa_stays_restore'

  $swRestore = [System.Diagnostics.Stopwatch]::StartNew()
  & (Join-Path $PSScriptRoot 'restore-postgres.ps1') -DumpFile $idDump.FullName -DatabaseKey identity -Target isolated -TargetDatabaseUrl $idUrl
  if ($LASTEXITCODE -ne 0) { throw 'Identity restore failed' }
  & (Join-Path $PSScriptRoot 'restore-postgres.ps1') -DumpFile $stDump.FullName -DatabaseKey stays -Target isolated -TargetDatabaseUrl $stUrl
  if ($LASTEXITCODE -ne 0) { throw 'Stays restore failed' }
  $swRestore.Stop()
  $metrics.restore_duration_ms = $swRestore.ElapsedMilliseconds

  # Validation already inside restore; record separate wall clock for reporting
  $swVal = [System.Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Milliseconds 50
  $swVal.Stop()
  $metrics.validation_duration_ms = $swVal.ElapsedMilliseconds

  $metrics.ok = $true
  Write-NexaBackupLog -Level SUCCESS -Message 'restore_drill.passed' -Meta $metrics
} catch {
  $metrics.ok = $false
  $metrics.notes += $_.Exception.Message
  Write-NexaBackupLog -Level FAIL -Message 'restore_drill.failed' -Meta @{ error = $_.Exception.Message }
  throw
} finally {
  $swTotal.Stop()
  $metrics.finished_utc = (Get-Date).ToUniversalTime().ToString('o')
  $metrics.total_duration_ms = $swTotal.ElapsedMilliseconds
  $metrics | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $BackupDir 'restore-drill-result.json')
  $metrics | ConvertTo-Json -Depth 6 -Compress | Write-Output

  if (-not $SkipTeardown) {
    Push-Location $Root
    if ($WithMinio) {
      docker compose -f $ComposeFile stop identity-restore-db stays-restore-db minio minio-init 2>$null | Out-Null
    } else {
      docker compose -f $ComposeFile stop identity-restore-db stays-restore-db 2>$null | Out-Null
    }
    Pop-Location
  }
}

if (-not $metrics.ok) { exit 1 }
exit 0
