# Phase 2 verification, decryption and restore. REVIEW ONLY; never executed.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EncryptedArchive,[Parameter(Mandatory)][string]$ManifestPath,
      [Parameter(Mandatory)][string]$SignaturePath,[Parameter(Mandatory)][string]$TrustedVerificationPublicKey,
      [Parameter(Mandatory)][string]$AgeIdentity,[Parameter(Mandatory)][string]$RestrictedTempDirectory,
      [Parameter(Mandatory)][string]$ExpectedArchiveId,[Parameter(Mandatory)][datetimeoffset]$MinimumBackupUtc,
      [ValidateRange(1,720)][int]$MaximumAgeHours=24)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Lab-Process.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$compose=Join-Path $root 'infrastructure/docker/compose.phase2.yaml'
Assert-LabImageDigest $compose
Assert-LabTargetPreflight $compose
$encrypted=Assert-LabSecurePath $EncryptedArchive
$manifest=Assert-LabSecurePath $ManifestPath
$sig=Assert-LabSecurePath $SignaturePath
$public=Assert-LabSecurePath $TrustedVerificationPublicKey
$identity=Assert-LabSecurePath $AgeIdentity -RequirePrivateAcl
$tempRoot=Assert-LabSecurePath $RestrictedTempDirectory -Directory -RequirePrivateAcl
if($tempRoot -eq $root -or $tempRoot.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Temporary plaintext cannot be inside repository'}
# G3: independent trusted public key; signature covers exact manifest bytes.
$null=Invoke-LabProcess openssl @('pkeyutl','-verify','-rawin','-pubin','-inkey',$public,'-sigfile',$sig,'-in',$manifest)
$m=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if($m.format -cne 'cloud-dr-lab-manifest-v2' -or $m.archive_id -cne $ExpectedArchiveId -or
   $m.encrypted_filename -cne [IO.Path]::GetFileName($encrypted) -or
   $m.marker_id -cne $ExpectedArchiveId -or $m.postgres_major -ne 17 -or
   $m.expectations_version -cne 'synthetic-seed-v1' -or $m.archive_format -cne 'pg_dump-custom' -or
   @($m.scope).Count -ne 2 -or -not (@($m.scope) -ccontains 'lab') -or -not (@($m.scope) -ccontains 'lab_dr')){throw 'Manifest identity or scope mismatch'}
$created=[datetimeoffset]::Parse($m.created_utc)
if($created -lt $MinimumBackupUtc -or $created -gt [datetimeoffset]::UtcNow.AddMinutes(5) -or
   ([datetimeoffset]::UtcNow-$created).TotalHours -gt $MaximumAgeHours){throw 'Signed backup is stale or unapproved'}
if((Get-Item -LiteralPath $encrypted).Length -ne [long]$m.encrypted_bytes -or
   (Get-FileHash -LiteralPath $encrypted -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.encrypted_sha256){throw 'Encrypted archive modified'}
$g3=[pscustomobject]@{gate='manifest_auth';verified=$true;signature_exit=0;hash_verified=$true;archive_id=$m.archive_id}
$temp=Join-Path $tempRoot ("cloud-dr-"+[guid]::NewGuid().ToString('N')+'.dump')
try {
    # G4: output file is exclusive, private temp dir; no PowerShell text pipeline.
    $null=Invoke-LabProcess age @('-d','-i',$identity,'-o',$temp,$encrypted) -TimeoutSeconds 180
    if((Get-Item -LiteralPath $temp -ErrorAction Stop).Length -lt 100){throw 'Decrypted archive too small'}
    $null=Invoke-LabProcess pg_restore @('--list',$temp) -TimeoutSeconds 90
    $g4=[pscustomobject]@{gate='decryption';verified=$true;age_exit=0;archive_list_exit=0}
    # Recheck the target immediately before restore. Fail closed on existing schemas.
    Assert-LabTargetPreflight $compose
    # G5: pg_restore consumes binary archive on stdin. --single-transaction implies exit-on-error.
    $r=Invoke-LabProcess docker @('compose','-f',$compose,'exec','-T','restore','pg_restore','-U','lab_owner','-d','labdb','--single-transaction','--exit-on-error','--no-owner') -StdinFile $temp -TimeoutSeconds 300
    if($r.ExitCode -ne 0){throw 'pg_restore failed'}
    [pscustomobject]@{manifest_auth=$g3;decryption=$g4;restore=[pscustomobject]@{gate='restore';verified=$true;exit=0};marker_id=$m.marker_id}
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $temp){throw 'STOP: plaintext temporary archive cleanup failed'}
}
