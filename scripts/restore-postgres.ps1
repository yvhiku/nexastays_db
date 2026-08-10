#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Restore a Nexa Postgres custom-format dump into an isolated (default) or explicitly confirmed target.
#>
param(
  [Parameter(Mandatory)][string]$DumpFile,
  [Parameter(Mandatory)][ValidateSet('identity','stays')][string]$DatabaseKey,
  [ValidateSet('isolated','staging','production')][string]$Target = 'isolated',
  [Parameter(Mandatory)][string]$TargetDatabaseUrl,
  [switch]$SkipDropSchema
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\NexaBackup.Common.ps1')

function Assert-RestoreAllowed {
  param([string]$Target)
  if ($Target -eq 'isolated') { return }
  $confirm = Get-EnvOrDefault 'RESTORE_CONFIRM' ''
  if ($confirm -ne 'YES') {
    throw "Destructive restore to '$Target' requires RESTORE_CONFIRM=YES"
  }
  if ($Target -eq 'production') {
    $allow = Get-EnvOrDefault 'RESTORE_ALLOW_PRODUCTION' ''
    if ($allow -ne 'YES') {
      throw 'Production restore rejected. Set RESTORE_ALLOW_PRODUCTION=YES only with explicit authorization.'
    }
  }
}

function Invoke-PsqlQuery {
  param($Conn, [string]$Sql, $Client)
  if ($Client.Mode -eq 'local') {
    $env:PGPASSWORD = $Conn.Password
    try {
      $args = @('-h', $Conn.Host, '-p', $Conn.Port, '-U', $Conn.User, '-d', $Conn.Database, '-v', 'ON_ERROR_STOP=1', '-tA', '-c', $Sql)
      $outFile = [System.IO.Path]::GetTempFileName()
      $errFile = "$outFile.err"
      $proc = Start-Process -FilePath $Client.Psql -ArgumentList $args -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
      if ($proc.ExitCode -ne 0) { throw "psql failed (exit $($proc.ExitCode))" }
      return (Get-Content -Raw $outFile).Trim()
    } finally {
      Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
      Remove-Item -Force -ErrorAction SilentlyContinue $outFile, $errFile
    }
  }

  $hostForDocker = $Conn.Host
  if ($hostForDocker -in @('127.0.0.1', 'localhost')) { $hostForDocker = 'host.docker.internal' }
  $dockerArgs = @(
    'run', '--rm',
    '--add-host=host.docker.internal:host-gateway',
    '-e', "PGPASSWORD=$($Conn.Password)",
    $Client.DockerImage,
    'psql',
    '-h', $hostForDocker,
    '-p', "$($Conn.Port)",
    '-U', $Conn.User,
    '-d', $Conn.Database,
    '-v', 'ON_ERROR_STOP=1',
    '-tA',
    '-c', $Sql
  )
  $oldEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = & docker @dockerArgs 2>&1
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldEap
  }
  $text = ($raw | ForEach-Object { "$_" }) -join "`n"
  if ($code -ne 0) { throw "docker psql failed (exit $code)" }
  return $text.Trim()
}

try {
  Assert-RestoreAllowed -Target $Target
  if (-not (Test-Path -LiteralPath $DumpFile)) { throw "Dump not found: $DumpFile" }

  $client = Get-PostgresClientRunner
  $conn = ConvertFrom-DatabaseUrl -Url $TargetDatabaseUrl

  Write-NexaBackupLog -Level INFO -Message 'restore.started' -Meta @{
    target = $Target
    database_key = $DatabaseKey
    connection = $conn.Redacted
    dump = (Split-Path $DumpFile -Leaf)
    client = $client.Mode
  }

  $tables = Get-ExpectedTables -DatabaseKey $DatabaseKey
  $null = Test-PgDumpArchive -DumpPath $DumpFile -ExpectedTables $tables -Client $client

  if (-not $SkipDropSchema) {
    Write-NexaBackupLog -Level WARN -Message 'restore.drop_schema' -Meta @{ target = $Target; connection = $conn.Redacted }
    $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO PUBLIC;'
  }

  $dir = Split-Path $DumpFile -Parent
  $leaf = Split-Path $DumpFile -Leaf
  if ($client.Mode -eq 'local') {
    $env:PGPASSWORD = $conn.Password
    try {
      $args = @(
        '-h', $conn.Host, '-p', $conn.Port, '-U', $conn.User, '-d', $conn.Database,
        '--clean', '--if-exists', '--no-owner', '--no-acl',
        $DumpFile
      )
      $errFile = [System.IO.Path]::GetTempFileName()
      $proc = Start-Process -FilePath $client.PgRestore -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
      if ($proc.ExitCode -notin 0, 1) {
        throw "pg_restore failed (exit $($proc.ExitCode))"
      }
    } finally {
      Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
      Remove-Item -Force -ErrorAction SilentlyContinue $errFile
    }
  } else {
    $hostForDocker = $conn.Host
    if ($hostForDocker -in @('127.0.0.1', 'localhost')) { $hostForDocker = 'host.docker.internal' }
    $cname = 'nexa-pgrestore-' + [guid]::NewGuid().ToString('n').Substring(0, 10)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & docker create --name $cname `
        --add-host=host.docker.internal:host-gateway `
        -e "PGPASSWORD=$($conn.Password)" `
        $client.DockerImage sleep 600 | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'docker create failed for pg_restore helper' }
      & docker start $cname | Out-Null
      & docker cp $DumpFile "${cname}:/tmp/restore.dump"
      if ($LASTEXITCODE -ne 0) { throw 'docker cp dump into helper failed' }
      & docker exec $cname pg_restore `
        -h $hostForDocker -p "$($conn.Port)" -U $conn.User -d $conn.Database `
        --clean --if-exists --no-owner --no-acl /tmp/restore.dump 2>&1 | Out-Null
      $code = $LASTEXITCODE
      if ($code -notin 0, 1) {
        throw "docker exec pg_restore failed (exit $code)"
      }
    } finally {
      $ErrorActionPreference = $oldEap
      & docker rm -f $cname 2>$null | Out-Null
    }
  }

  foreach ($t in $tables) {
    $exists = Invoke-PsqlQuery -Conn $conn -Client $client -Sql "SELECT CASE WHEN to_regclass('public.$t') IS NULL THEN 'missing' ELSE 'ok' END"
    if ($exists -ne 'ok') {
      throw "Post-restore table missing: $t"
    }
  }

  foreach ($c in $script:NexaConstraintChecks[$DatabaseKey]) {
    $hit = Invoke-PsqlQuery -Conn $conn -Client $client -Sql $c.sql
    if ([string]::IsNullOrWhiteSpace($hit)) {
      throw "Post-restore constraint/index missing: $($c.name)"
    }
  }

  $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'SELECT COUNT(*) FROM schema_migrations'
  if ($DatabaseKey -eq 'identity') {
    $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'SELECT COUNT(*) FROM users'
  } else {
    $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'SELECT COUNT(*) FROM stays_bookings'
    $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'SELECT COUNT(*) FROM stays_payment_intents'
    $null = Invoke-PsqlQuery -Conn $conn -Client $client -Sql 'SELECT COUNT(*) FROM stays_ledger_entries'
  }

  Write-NexaBackupLog -Level SUCCESS -Message 'restore.completed' -Meta @{
    target = $Target
    database_key = $DatabaseKey
    connection = $conn.Redacted
  }
  @{ ok = $true; target = $Target; database = $DatabaseKey } | ConvertTo-Json -Compress | Write-Output
  exit 0
} catch {
  Write-NexaBackupLog -Level FAIL -Message 'restore.failed' -Meta @{ error = $_.Exception.Message }
  @{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress | Write-Output
  exit 1
}
