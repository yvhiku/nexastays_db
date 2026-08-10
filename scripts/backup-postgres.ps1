#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Logical backup (pg_dump -Fc) for Nexa Identity and/or Stays Postgres databases.

.DESCRIPTION
  Required env:
    BACKUP_DIR
    IDENTITY_DATABASE_URL and/or STAYS_DATABASE_URL (depending on -Database)

  Optional:
    BACKUP_RETENTION_DAYS (default 30)
    BACKUP_REMOTE_ENABLED (true/false)
    BACKUP_REMOTE_PROVIDER (filesystem|s3)
    BACKUP_REMOTE_PATH (filesystem destination OR s3 object prefix)
    S3_ENDPOINT S3_BUCKET S3_REGION S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY

  Never prints passwords. Exit 0 only when dump + integrity + optional remote succeed.
#>
param(
  [ValidateSet('all','identity','stays')]
  [string]$Database = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Lib = Join-Path $PSScriptRoot 'lib\NexaBackup.Common.ps1'
. $Lib

$result = [ordered]@{
  ok       = $false
  started  = (Get-Date).ToUniversalTime().ToString('o')
  backups  = @()
  errors   = @()
}

try {
  $backupDir = Get-RequiredEnv 'BACKUP_DIR'
  $retention = [int](Get-EnvOrDefault 'BACKUP_RETENTION_DAYS' '30')
  Assert-SecureBackupDirectory -Path $backupDir

  $client = Get-PostgresClientRunner
  Write-NexaBackupLog -Level INFO -Message 'backup.client' -Meta @{ mode = $client.Mode }

  $targets = @()
  if ($Database -eq 'all' -or $Database -eq 'identity') { $targets += 'identity' }
  if ($Database -eq 'all' -or $Database -eq 'stays') { $targets += 'stays' }

  $ts = New-BackupTimestamp
  Write-NexaBackupLog -Level INFO -Message 'backup.started' -Meta @{
    databases = ($targets -join ',')
    backup_dir = $backupDir
    timestamp = $ts
  }

  foreach ($key in $targets) {
    $envName = if ($key -eq 'identity') { 'IDENTITY_DATABASE_URL' } else { 'STAYS_DATABASE_URL' }
    $url = Get-RequiredEnv $envName
    $conn = ConvertFrom-DatabaseUrl -Url $url
    $fileName = Get-BackupFileName -DatabaseKey $key -Timestamp $ts
    $outFile = Join-Path $backupDir $fileName
    $tmpFile = "$outFile.partial"

    Write-NexaBackupLog -Level INFO -Message 'backup.dump.begin' -Meta @{
      database = $key
      connection = $conn.Redacted
      file = $fileName
    }

    if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }
    Invoke-PgDumpCustom -Conn $conn -OutFile $tmpFile -Client $client
    Move-Item -LiteralPath $tmpFile -Destination $outFile -Force

    $tables = Get-ExpectedTables -DatabaseKey $key
    $integrity = Test-PgDumpArchive -DumpPath $outFile -ExpectedTables $tables -Client $client

    $remoteUri = $null
    $remoteEnabled = (Get-EnvOrDefault 'BACKUP_REMOTE_ENABLED' 'false').ToLowerInvariant() -eq 'true'
    if ($remoteEnabled) {
      $provider = (Get-EnvOrDefault 'BACKUP_REMOTE_PROVIDER' 'filesystem').ToLowerInvariant()
      if ($provider -eq 'filesystem') {
        $remotePath = Get-RequiredEnv 'BACKUP_REMOTE_PATH'
        $remoteUri = Copy-BackupToRemoteFilesystem -SourceFile $outFile -RemotePath $remotePath
      } elseif ($provider -eq 's3') {
        $bucket = Get-RequiredEnv 'S3_BUCKET'
        $prefix = (Get-EnvOrDefault 'BACKUP_REMOTE_PATH' '').Trim('/').Trim()
        $objectKey = if ($prefix) { "$prefix/$fileName" } else { $fileName }
        $remoteUri = Copy-BackupToS3Compatible `
          -SourceFile $outFile `
          -Bucket $bucket `
          -ObjectKey $objectKey `
          -Endpoint (Get-EnvOrDefault 'S3_ENDPOINT' '') `
          -Region (Get-EnvOrDefault 'S3_REGION' 'us-east-1') `
          -AccessKey (Get-EnvOrDefault 'S3_ACCESS_KEY_ID' '') `
          -SecretKey (Get-EnvOrDefault 'S3_SECRET_ACCESS_KEY' '')
      } else {
        throw "Unsupported BACKUP_REMOTE_PROVIDER: $provider"
      }
      Write-NexaBackupLog -Level SUCCESS -Message 'backup.remote.ok' -Meta @{
        database = $key
        provider = $provider
        remote = $remoteUri
      }
    }

    $removed = @(Invoke-RetentionCleanup -BackupDir $backupDir -DatabaseKey $key -RetentionDays $retention)
    Write-NexaBackupLog -Level INFO -Message 'backup.retention' -Meta @{
      database = $key
      retention_days = $retention
      removed_count = @($removed).Count
    }

    $entry = [ordered]@{
      database = $key
      file     = $outFile
      bytes    = $integrity.bytes
      remote   = $remoteUri
    }
    $result.backups += $entry
    Write-NexaBackupLog -Level SUCCESS -Message 'backup.database.ok' -Meta $entry
  }

  $result.ok = $true
  $result.finished = (Get-Date).ToUniversalTime().ToString('o')
  Write-NexaBackupLog -Level SUCCESS -Message 'backup.completed' -Meta @{ count = $result.backups.Count }
  $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
  exit 0
} catch {
  $result.ok = $false
  $result.errors += $_.Exception.Message
  Write-NexaBackupLog -Level FAIL -Message 'backup.failed' -Meta @{ error = $_.Exception.Message }
  $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
  exit 1
}
