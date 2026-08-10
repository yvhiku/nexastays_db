#!/usr/bin/env pwsh
# Unit tests for retention + safety helpers (no live DB required).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\NexaBackup.Common.ps1')

$failed = 0
function Assert-True($cond, $msg) {
  if (-not $cond) {
    Write-Host "FAIL: $msg"
    $script:failed++
  } else {
    Write-Host "PASS: $msg"
  }
}

# --- ConvertFrom-DatabaseUrl ---
$conn = ConvertFrom-DatabaseUrl 'postgresql://user:s3cret@host.example:5433/mydb'
Assert-True ($conn.User -eq 'user') 'parse user'
Assert-True ($conn.Password -eq 's3cret') 'parse password'
Assert-True ($conn.Redacted -notmatch 's3cret') 'redacted omits password'
Assert-True ($conn.Redacted -match '\*\*\*') 'redacted marker'

try {
  ConvertFrom-DatabaseUrl 'not-a-url' | Out-Null
  Assert-True $false 'invalid url should throw'
} catch {
  Assert-True $true 'invalid url throws'
}

# --- Retention ---
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nexa-backup-test-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $now = Get-Date
  # newest
  $fNew = Join-Path $tmp 'identity_2099-01-02_03-04-05.dump'
  Set-Content -Path $fNew -Value 'x'
  (Get-Item $fNew).LastWriteTimeUtc = $now.ToUniversalTime()

  # old
  $fOld = Join-Path $tmp 'identity_2020-01-02_03-04-05.dump'
  Set-Content -Path $fOld -Value 'y'
  (Get-Item $fOld).LastWriteTimeUtc = $now.ToUniversalTime().AddDays(-40)

  # invalid name ignored
  $fBad = Join-Path $tmp 'identity_weird.dump'
  Set-Content -Path $fBad -Value 'z'
  (Get-Item $fBad).LastWriteTimeUtc = $now.ToUniversalTime().AddDays(-40)

  # today-ish second file should not be deleted even if "old" retention if same day
  $fToday = Join-Path $tmp 'identity_2099-01-02_01-01-01.dump'
  Set-Content -Path $fToday -Value 't'
  (Get-Item $fToday).LastWriteTimeUtc = $now.ToUniversalTime()

  $victims = @(Get-RetentionCandidates -BackupDir $tmp -DatabaseKey identity -RetentionDays 30)
  Assert-True ($victims.Count -eq 1) 'exactly one retention victim'
  Assert-True ($victims[0].Name -eq 'identity_2020-01-02_03-04-05.dump') 'old dump selected'
  Assert-True ($victims[0].FullName -ne $fNew) 'newest not selected'

  $removed = @(Invoke-RetentionCleanup -BackupDir $tmp -DatabaseKey identity -RetentionDays 30)
  Assert-True ($removed.Count -eq 1) 'removed one'
  Assert-True (Test-Path $fNew) 'newest remains'
  Assert-True (-not (Test-Path $fOld)) 'old removed'
  Assert-True (Test-Path $fBad) 'invalid name untouched'

  # log redaction
  $out = & {
    Write-NexaBackupLog -Level INFO -Message 'test' -Meta @{ password = 'nope'; DATABASE_URL = 'postgresql://u:p@h/db'; ok = 1 }
  } 6>&1 | Out-String
  # Write-Host goes to success stream differently; capture via transcript alternative:
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# --- Restore guards ---
Remove-Item Env:RESTORE_CONFIRM -ErrorAction SilentlyContinue
Remove-Item Env:RESTORE_ALLOW_PRODUCTION -ErrorAction SilentlyContinue
$restoreScript = Join-Path $PSScriptRoot 'restore-postgres.ps1'
$fakeDump = Join-Path ([System.IO.Path]::GetTempPath()) 'missing.dump'
& $restoreScript -DumpFile $fakeDump -DatabaseKey identity -Target production -TargetDatabaseUrl 'postgresql://u:p@localhost:1/db' 2>$null | Out-Null
Assert-True ($LASTEXITCODE -ne 0) 'production restore without confirm fails'

$env:RESTORE_CONFIRM = 'YES'
& $restoreScript -DumpFile $fakeDump -DatabaseKey identity -Target production -TargetDatabaseUrl 'postgresql://u:p@localhost:1/db' 2>$null | Out-Null
Assert-True ($LASTEXITCODE -ne 0) 'production restore without ALLOW_PRODUCTION fails'
Remove-Item Env:RESTORE_CONFIRM -ErrorAction SilentlyContinue

# Naming
Assert-True ((Get-BackupFileName -DatabaseKey stays -Timestamp '2026-08-10_12-00-00') -eq 'stays_2026-08-10_12-00-00.dump') 'naming'

# --- Production remote policy ---
Remove-Item Env:NEXA_ENV -ErrorAction SilentlyContinue
Remove-Item Env:BACKUP_REQUIRE_REMOTE -ErrorAction SilentlyContinue
Remove-Item Env:BACKUP_REMOTE_ENABLED -ErrorAction SilentlyContinue
Assert-True (-not (Test-RemoteIsRequired)) 'remote not required by default'

$env:NEXA_ENV = 'production'
Assert-True (Test-RemoteIsRequired) 'production requires remote'
$env:BACKUP_REMOTE_ENABLED = 'false'
try {
  Assert-RemotePolicyConfigured
  Assert-True $false 'production without remote should throw'
} catch {
  Assert-True $true 'production without remote throws'
}

$env:BACKUP_REMOTE_ENABLED = 'true'
$env:BACKUP_REMOTE_PROVIDER = 's3'
$env:S3_BUCKET = 'b'
$env:S3_ACCESS_KEY_ID = 'ak'
$env:S3_SECRET_ACCESS_KEY = 'sk'
$env:S3_ENDPOINT = 'http://127.0.0.1:9000'
try {
  Assert-RemotePolicyConfigured
  Assert-True $false 'http endpoint in production should throw'
} catch {
  Assert-True $true 'http endpoint in production rejected'
}
$env:S3_ENDPOINT = 'https://s3.example.com'
Assert-RemotePolicyConfigured
Assert-True $true 'https s3 policy accepts'
Remove-Item Env:NEXA_ENV,Env:BACKUP_REMOTE_ENABLED,Env:BACKUP_REMOTE_PROVIDER,Env:S3_BUCKET,Env:S3_ACCESS_KEY_ID,Env:S3_SECRET_ACCESS_KEY,Env:S3_ENDPOINT -ErrorAction SilentlyContinue

if ($failed -gt 0) {
  Write-Host "FAILED=$failed"
  exit 1
}
Write-Host 'ALL_UNIT_TESTS_PASSED'
exit 0
