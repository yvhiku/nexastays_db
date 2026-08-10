# Shared helpers for Nexa Postgres backup/restore (PowerShell).
# Never log passwords or full DATABASE_URLs.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-NexaBackupLog {
  param(
    [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','SUCCESS','FAIL')]
    [string]$Level,
    [Parameter(Mandatory)][string]$Message,
    [hashtable]$Meta = @{}
  )
  $safe = @{}
  foreach ($k in $Meta.Keys) {
    $lk = $k.ToLowerInvariant()
    if ($lk -match 'password|secret|token|access_key|secret_key|DATABASE_URL') {
      $safe[$k] = '[REDACTED]'
    } else {
      $safe[$k] = $Meta[$k]
    }
  }
  $payload = [ordered]@{
    ts     = (Get-Date).ToUniversalTime().ToString('o')
    level  = $Level
    msg    = $Message
    meta   = $safe
  }
  $line = ($payload | ConvertTo-Json -Compress -Depth 6)
  Write-Host $line
}

function Get-RequiredEnv {
  param([Parameter(Mandatory)][string]$Name)
  $v = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($v)) {
    throw "Missing required environment variable: $Name"
  }
  return $v.Trim()
}

function Get-EnvOrDefault {
  param([string]$Name, [string]$Default = '')
  $v = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

function Get-PostgresClientRunner {
  <#
    Returns hashtable: Mode = local|docker, PgDump, PgRestore, Psql, DockerImage
  #>
  $localDump = Get-Command pg_dump -ErrorAction SilentlyContinue
  $localRestore = Get-Command pg_restore -ErrorAction SilentlyContinue
  $localPsql = Get-Command psql -ErrorAction SilentlyContinue
  if ($localDump -and $localRestore -and $localPsql) {
    return @{
      Mode       = 'local'
      PgDump     = $localDump.Source
      PgRestore  = $localRestore.Source
      Psql       = $localPsql.Source
      DockerImage = $null
    }
  }
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if (-not $docker) {
    throw 'PostgreSQL client tools (pg_dump/pg_restore/psql) not found, and Docker is unavailable for fallback.'
  }
  return @{
    Mode        = 'docker'
    PgDump      = 'pg_dump'
    PgRestore   = 'pg_restore'
    Psql        = 'psql'
    DockerImage = (Get-EnvOrDefault 'BACKUP_PG_IMAGE' 'postgres:16-alpine')
  }
}

function Invoke-DockerPgTool {
  param(
    [Parameter(Mandatory)]$Conn,
    [Parameter(Mandatory)][string]$DockerImage,
    [Parameter(Mandatory)][string]$Tool, # pg_dump|pg_restore|psql
    [Parameter(Mandatory)][string[]]$ToolArgs,
    [string]$MountHostDir = '',
    [string]$MountContainerDir = '/work'
  )
  $hostForDocker = $Conn.Host
  if ($hostForDocker -in @('127.0.0.1', 'localhost')) {
    $hostForDocker = 'host.docker.internal'
  }
  $dockerArgs = @(
    'run', '--rm',
    '--add-host=host.docker.internal:host-gateway',
    '-e', "PGPASSWORD=$($Conn.Password)"
  )
  if ($MountHostDir) {
    $resolved = (Resolve-Path $MountHostDir).Path
    $dockerArgs += @('-v', "${resolved}:${MountContainerDir}")
  }
  $dockerArgs += @(
    $DockerImage,
    $Tool,
    '-h', $hostForDocker,
    '-p', $Conn.Port,
    '-U', $Conn.User
  ) + $ToolArgs
  & docker @dockerArgs
  return $LASTEXITCODE
}

function ConvertFrom-DatabaseUrl {
  param([Parameter(Mandatory)][string]$Url)
  # postgresql://user:pass@host:port/db
  if ($Url -notmatch '^(?:postgres(?:ql)?://)([^:/?#]+):([^@]+)@([^:/?#]+)(?::(\d+))?/([^?/]+)') {
    throw 'Invalid DATABASE_URL format (expected postgresql://user:pass@host:port/db)'
  }
  return [pscustomobject]@{
    User     = $Matches[1]
    Password = $Matches[2]
    Host     = $Matches[3]
    Port     = if ($Matches[4]) { $Matches[4] } else { '5432' }
    Database = $Matches[5]
    Redacted = "postgresql://$($Matches[1]):***@$($Matches[3]):$(if ($Matches[4]) { $Matches[4] } else { '5432' })/$($Matches[5])"
  }
}

function New-BackupTimestamp {
  return (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HH-mm-ss')
}

function Get-BackupFileName {
  param(
    [Parameter(Mandatory)][ValidateSet('identity','stays')][string]$DatabaseKey,
    [Parameter(Mandatory)][string]$Timestamp
  )
  return "${DatabaseKey}_${Timestamp}.dump"
}

function Assert-SecureBackupDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
  # Best-effort ACL tighten on Windows (ignore failure on non-NTFS / restricted hosts).
  try {
    icacls $Path /inheritance:r 2>$null | Out-Null
    icacls $Path /grant:r "${env:USERNAME}:(OI)(CI)F" 2>$null | Out-Null
  } catch {
    Write-NexaBackupLog -Level WARN -Message 'Could not tighten backup directory ACL' -Meta @{ path = $Path }
  }
}

function Test-PgDumpArchive {
  param(
    [Parameter(Mandatory)][string]$DumpPath,
    [Parameter(Mandatory)][string[]]$ExpectedTables,
    $Client = $null
  )
  if (-not (Test-Path -LiteralPath $DumpPath)) {
    throw "Backup file missing: $DumpPath"
  }
  $item = Get-Item -LiteralPath $DumpPath
  if ($item.Length -le 0) {
    throw "Backup file is empty: $DumpPath"
  }
  if (-not $Client) { $Client = Get-PostgresClientRunner }

  $listText = ''
  if ($Client.Mode -eq 'local') {
    $listFile = [System.IO.Path]::GetTempFileName()
    try {
      $proc = Start-Process -FilePath $Client.PgRestore -ArgumentList @('--list', $DumpPath) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $listFile -RedirectStandardError "$listFile.err"
      if ($proc.ExitCode -ne 0) {
        throw "pg_restore --list failed (exit $($proc.ExitCode))"
      }
      $listText = Get-Content -Raw $listFile
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $listFile, "$listFile.err"
    }
  } else {
    $dir = Split-Path $DumpPath -Parent
    $leaf = Split-Path $DumpPath -Leaf
    $listText = & docker run --rm -v "${dir}:/work:ro" $Client.DockerImage pg_restore --list "/work/$leaf"
    if ($LASTEXITCODE -ne 0) { throw "docker pg_restore --list failed (exit $LASTEXITCODE)" }
    $listText = ($listText | Out-String)
  }

  if ([string]::IsNullOrWhiteSpace($listText)) {
    throw 'pg_restore --list produced empty TOC'
  }
  if ($listText -notmatch 'TABLE') {
    throw 'Archive TOC contains no TABLE entries'
  }
  foreach ($t in $ExpectedTables) {
    if ($listText -notmatch [regex]::Escape($t)) {
      throw "Archive missing expected table object: $t"
    }
  }
  return @{
    ok         = $true
    bytes      = $item.Length
    tableHits  = $ExpectedTables.Count
  }
}

function Invoke-PgDumpCustom {
  param(
    [Parameter(Mandatory)]$Conn,
    [Parameter(Mandatory)][string]$OutFile,
    $Client = $null
  )
  if (-not $Client) { $Client = Get-PostgresClientRunner }
  $dir = Split-Path $OutFile -Parent
  $leaf = Split-Path $OutFile -Leaf

  if ($Client.Mode -eq 'local') {
    $env:PGPASSWORD = $Conn.Password
    try {
      $args = @(
        '-h', $Conn.Host, '-p', $Conn.Port, '-U', $Conn.User, '-d', $Conn.Database,
        '-F', 'c', '-b', '-f', $OutFile
      )
      $errFile = [System.IO.Path]::GetTempFileName()
      $proc = Start-Process -FilePath $Client.PgDump -ArgumentList $args `
        -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
      if ($proc.ExitCode -ne 0) {
        throw "pg_dump failed for database $($Conn.Database) (exit $($proc.ExitCode))"
      }
    } finally {
      Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
      Remove-Item -Force -ErrorAction SilentlyContinue $errFile
    }
  } else {
    $code = Invoke-DockerPgTool -Conn $Conn -DockerImage $Client.DockerImage -Tool 'pg_dump' `
      -MountHostDir $dir -ToolArgs @('-d', $Conn.Database, '-F', 'c', '-b', '-f', "/work/$leaf")
    if ($code -ne 0) {
      throw "docker pg_dump failed for database $($Conn.Database) (exit $code)"
    }
  }

  if (-not (Test-Path -LiteralPath $OutFile) -or ((Get-Item $OutFile).Length -le 0)) {
    throw "pg_dump did not produce a usable file for $($Conn.Database)"
  }
}

function Get-RetentionCandidates {
  <#
    Returns list of files that MAY be deleted under retention rules.
    Never includes:
      - files newer than retention cutoff
      - the newest valid dump overall
      - files not matching naming pattern
  #>
  param(
    [Parameter(Mandatory)][string]$BackupDir,
    [Parameter(Mandatory)][ValidateSet('identity','stays')][string]$DatabaseKey,
    [Parameter(Mandatory)][int]$RetentionDays
  )
  if ($RetentionDays -lt 1) { throw 'BACKUP_RETENTION_DAYS must be >= 1' }
  $pattern = "^${DatabaseKey}_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.dump$"
  $files = @(Get-ChildItem -LiteralPath $BackupDir -File -Filter "$DatabaseKey`_*.dump" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $pattern } |
    Sort-Object LastWriteTimeUtc -Descending)

  if ($files.Count -eq 0) { return @() }

  $newest = $files[0]
  $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $RetentionDays)
  $todayUtc = (Get-Date).ToUniversalTime().Date

  $toDelete = [System.Collections.Generic.List[object]]::new()
  foreach ($f in $files) {
    if ($f.FullName -eq $newest.FullName) { continue }
    if ($f.LastWriteTimeUtc -ge $todayUtc) { continue } # never delete today's backup
    if ($f.LastWriteTimeUtc -lt $cutoff) {
      [void]$toDelete.Add($f)
    }
  }
  return @($toDelete.ToArray())
}

function Invoke-RetentionCleanup {
  param(
    [Parameter(Mandatory)][string]$BackupDir,
    [Parameter(Mandatory)][ValidateSet('identity','stays')][string]$DatabaseKey,
    [Parameter(Mandatory)][int]$RetentionDays
  )
  $victims = @(Get-RetentionCandidates -BackupDir $BackupDir -DatabaseKey $DatabaseKey -RetentionDays $RetentionDays)
  $removedNames = [System.Collections.Generic.List[string]]::new()
  foreach ($f in $victims) {
    if ($null -eq $f) { continue }
    $path = $f.FullName
    Remove-Item -LiteralPath $path -Force
    [void]$removedNames.Add($f.Name)
  }
  return @($removedNames.ToArray())
}

function Copy-BackupToRemoteFilesystem {
  param(
    [Parameter(Mandatory)][string]$SourceFile,
    [Parameter(Mandatory)][string]$RemotePath
  )
  if (-not (Test-Path -LiteralPath $RemotePath)) {
    New-Item -ItemType Directory -Path $RemotePath -Force | Out-Null
  }
  $dest = Join-Path $RemotePath (Split-Path $SourceFile -Leaf)
  Copy-Item -LiteralPath $SourceFile -Destination $dest -Force
  if (-not (Test-Path -LiteralPath $dest) -or ((Get-Item $dest).Length -le 0)) {
    throw 'Remote filesystem copy produced missing/empty file'
  }
  return $dest
}

function Copy-BackupToS3Compatible {
  param(
    [Parameter(Mandatory)][string]$SourceFile,
    [Parameter(Mandatory)][string]$Bucket,
    [Parameter(Mandatory)][string]$ObjectKey,
    [string]$Endpoint = '',
    [string]$Region = 'us-east-1',
    [string]$AccessKey = '',
    [string]$SecretKey = ''
  )
  $aws = Get-Command aws -ErrorAction SilentlyContinue
  $uri = "s3://$Bucket/$ObjectKey"

  if ($aws) {
    if ($AccessKey) { $env:AWS_ACCESS_KEY_ID = $AccessKey }
    if ($SecretKey) { $env:AWS_SECRET_ACCESS_KEY = $SecretKey }
    if ($Region) { $env:AWS_DEFAULT_REGION = $Region }
    try {
      $args = @('s3', 'cp', $SourceFile, $uri)
      if ($Endpoint) { $args += @('--endpoint-url', $Endpoint) }
      $errFile = [System.IO.Path]::GetTempFileName()
      $proc = Start-Process -FilePath $aws.Source -ArgumentList $args `
        -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile -RedirectStandardOutput "$errFile.out"
      if ($proc.ExitCode -ne 0) {
        throw "aws s3 cp failed (exit $($proc.ExitCode))"
      }
      return $uri
    } finally {
      Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
      Remove-Item -Force -ErrorAction SilentlyContinue $errFile, "$errFile.out"
    }
  }

  # Prefer minio client when endpoint is set and `mc` image is available (faster than aws-cli pull).
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($docker -and $Endpoint) {
    $srcDir = (Resolve-Path (Split-Path $SourceFile -Parent)).Path
    $leaf = Split-Path $SourceFile -Leaf
    $endpointForDocker = $Endpoint
    if ($Endpoint -match '127\.0\.0\.1|localhost') {
      $endpointForDocker = $Endpoint -replace '127\.0\.0\.1','host.docker.internal' -replace 'localhost','host.docker.internal'
    }
    $mcScript = @"
mc alias set nexa '$endpointForDocker' '$AccessKey' '$SecretKey' >/dev/null
mc mb -p "nexa/$Bucket" >/dev/null || true
mc cp "/backup/$leaf" "nexa/$Bucket/$ObjectKey"
"@
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      # minio/mc image entrypoint is `mc`; override to run a shell script.
      & docker run --rm --add-host=host.docker.internal:host-gateway `
        --entrypoint /bin/sh `
        -v "${srcDir}:/backup:ro" `
        minio/mc:latest `
        -c $mcScript 2>&1 | Out-Null
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $oldEap
    }
    if ($code -eq 0) {
      return "s3://$Bucket/$ObjectKey"
    }
    throw "S3-compatible upload via minio/mc failed (exit $code). Install AWS CLI or ensure MinIO endpoint is reachable."
  }

  throw 'S3 remote requires AWS CLI (`aws`) on PATH, or Docker + MinIO endpoint for minio/mc upload.'
}

$script:NexaExpectedTables = @{
  identity = @(
    'users',
    'refresh_tokens',
    'otp_codes',
    'schema_migrations'
  )
  stays = @(
    'stays_listings',
    'stays_bookings',
    'stays_payment_intents',
    'stays_ledger_entries',
    'schema_migrations'
  )
}

$script:NexaConstraintChecks = @{
  identity = @(
    @{ name = 'users_pkey'; sql = "SELECT 1 FROM pg_constraint WHERE conname = 'users_pkey' LIMIT 1" }
  )
  stays = @(
    @{ name = 'ex_stays_bookings_active_overlap'; sql = "SELECT 1 FROM pg_constraint WHERE conname = 'ex_stays_bookings_active_overlap' LIMIT 1" }
    @{ name = 'idx_stays_ledger_settled_guest_payment_unique'; sql = "SELECT 1 FROM pg_indexes WHERE indexname = 'idx_stays_ledger_settled_guest_payment_unique' LIMIT 1" }
    @{ name = 'stays_bookings_pkey'; sql = "SELECT 1 FROM pg_constraint WHERE conname = 'stays_bookings_pkey' LIMIT 1" }
  )
}

function Get-ExpectedTables {
  param([ValidateSet('identity','stays')][string]$DatabaseKey)
  return $script:NexaExpectedTables[$DatabaseKey]
}

function Test-RemoteIsRequired {
  $nexa = (Get-EnvOrDefault 'NEXA_ENV' '').ToLowerInvariant()
  $flag = (Get-EnvOrDefault 'BACKUP_REQUIRE_REMOTE' 'false').ToLowerInvariant()
  return ($nexa -eq 'production' -or $flag -eq 'true')
}

function Assert-RemotePolicyConfigured {
  if (-not (Test-RemoteIsRequired)) { return }
  $enabled = (Get-EnvOrDefault 'BACKUP_REMOTE_ENABLED' 'false').ToLowerInvariant()
  if ($enabled -ne 'true') {
    throw 'NEXA_ENV=production (or BACKUP_REQUIRE_REMOTE=true) requires BACKUP_REMOTE_ENABLED=true'
  }
  $provider = (Get-EnvOrDefault 'BACKUP_REMOTE_PROVIDER' 'filesystem').ToLowerInvariant()
  if ($provider -eq 'filesystem') {
    [void](Get-RequiredEnv 'BACKUP_REMOTE_PATH')
  } elseif ($provider -eq 's3') {
    [void](Get-RequiredEnv 'S3_BUCKET')
    [void](Get-RequiredEnv 'S3_ACCESS_KEY_ID')
    [void](Get-RequiredEnv 'S3_SECRET_ACCESS_KEY')
    $nexa = (Get-EnvOrDefault 'NEXA_ENV' '').ToLowerInvariant()
    $ep = (Get-EnvOrDefault 'S3_ENDPOINT' '')
    if ($nexa -eq 'production' -and $ep -and -not $ep.StartsWith('https://')) {
      throw 'production S3_ENDPOINT must use https://'
    }
  } else {
    throw "Unsupported BACKUP_REMOTE_PROVIDER: $provider"
  }
}

function Get-FileSha256Hex {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-BackupManifest {
  param(
    [Parameter(Mandatory)][string]$DatabaseKey,
    [Parameter(Mandatory)][string]$DumpPath,
    [Parameter(Mandatory)][long]$Bytes,
    [Parameter(Mandatory)][string]$Sha256,
    $Remote = $null
  )
  $manifest = [ordered]@{
    database       = $DatabaseKey
    file           = (Split-Path $DumpPath -Leaf)
    bytes          = $Bytes
    sha256         = $Sha256
    timestamp_utc  = (Get-Date).ToUniversalTime().ToString('o')
    remote         = $Remote
  }
  $out = "$DumpPath.manifest.json"
  ($manifest | ConvertTo-Json -Depth 6 -Compress) | Set-Content -LiteralPath $out -Encoding utf8
  Write-NexaBackupLog -Level INFO -Message 'backup.manifest' -Meta @{
    database = $DatabaseKey
    path     = (Split-Path $out -Leaf)
  }
}
