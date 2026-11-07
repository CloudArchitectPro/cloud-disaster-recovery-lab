# Eight-gate recovery orchestrator. REVIEW ONLY; NOT EXECUTED.
# Gate results come exclusively from child process outcomes and database assertions.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Recipient,[Parameter(Mandatory)][string]$SigningPrivateKey,
      [Parameter(Mandatory)][string]$TrustedVerificationPublicKey,[Parameter(Mandatory)][string]$AgeIdentity,
      [Parameter(Mandatory)][string]$ArtifactDirectory,[Parameter(Mandatory)][string]$RestrictedTempDirectory,
      [Parameter(Mandatory)][string]$EvidenceDirectory,[Parameter(Mandatory)][datetimeoffset]$MinimumBackupUtc,
      [Parameter(Mandatory)][datetimeoffset]$IncidentUtc,[ValidateRange(1,720)][int]$MaximumAgeHours=24)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Lab-Process.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$source=Join-Path $root 'infrastructure/docker/compose.yaml'
$target=Join-Path $root 'infrastructure/docker/compose.phase2.yaml'
$evidenceRoot=Assert-LabSecurePath $EvidenceDirectory -Directory -RequirePrivateAcl
if($evidenceRoot -eq $root -or $evidenceRoot.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence directory must be outside repository'}
$gates=[ordered]@{}
foreach($g in @('backup','encryption','manifest_auth','decryption','restore','data','security','recovery_evidence')){$gates[$g]='NOT_RUN'}
$runId=[guid]::NewGuid().ToString('D')
$watch=[Diagnostics.Stopwatch]::StartNew();$started=[datetimeoffset]::UtcNow
$active='backup';$archiveId=$null;$failure=$null
try {
    Assert-LabSourcePreflight $source
    Assert-LabImageDigest $target
    Assert-LabTargetPreflight $target
    $backup=& (Join-Path $PSScriptRoot 'Backup-LabDatabase.ps1') -Recipient $Recipient -SigningPrivateKey $SigningPrivateKey -ArtifactDirectory $ArtifactDirectory
    if($backup.dump_exit -ne 0 -or $backup.age_exit -ne 0 -or $backup.signing_exit -ne 0){throw 'Backup process exits not successful'}
    $archiveId=$backup.archive_id
    if([guid]::Parse($archiveId).ToString('D') -cne $archiveId){throw 'Invalid archive identifier'}
    $gates.backup='PASS';$gates.encryption='PASS'
    $active='manifest_auth'
    $restore=& (Join-Path $PSScriptRoot 'Restore-LabDatabase.ps1') -EncryptedArchive $backup.encrypted_archive -ManifestPath $backup.manifest -SignaturePath $backup.signature -TrustedVerificationPublicKey $TrustedVerificationPublicKey -AgeIdentity $AgeIdentity -RestrictedTempDirectory $RestrictedTempDirectory -ExpectedArchiveId $archiveId -MinimumBackupUtc $MinimumBackupUtc -MaximumAgeHours $MaximumAgeHours
    if(-not $restore.manifest_auth.verified -or $restore.manifest_auth.signature_exit -ne 0 -or -not $restore.manifest_auth.hash_verified){throw 'Manifest attestation failed'}
    $gates.manifest_auth='PASS';$active='decryption'
    if(-not $restore.decryption.verified -or $restore.decryption.age_exit -ne 0 -or $restore.decryption.archive_list_exit -ne 0){throw 'Decryption attestation failed'}
    $gates.decryption='PASS';$active='restore'
    if(-not $restore.restore.verified -or $restore.restore.exit -ne 0){throw 'Restore attestation failed'}
    $gates.restore='PASS';$active='data'
    $tests=& (Join-Path $PSScriptRoot 'Test-LabRecovery.ps1') -ExpectedMarkerId ([guid]$archiveId)
    if(-not $tests.data.verified -or $tests.data.assertions -lt 8){throw 'Data validation incomplete'}
    $gates.data='PASS';$active='security'
    if(-not $tests.security.verified -or $tests.security.assertions -lt 15){throw 'Security validation incomplete'}
    $gates.security='PASS';$active='recovery_evidence'
    $accepted=[datetimeoffset]::UtcNow
    if($IncidentUtc -lt [datetimeoffset]::Parse($backup.marker_acknowledged_utc) -or $accepted -lt $IncidentUtc){throw 'Invalid incident/marker timestamps'}
    $measurement=[ordered]@{
        marker_age_proxy_seconds=[math]::Round(($IncidentUtc-[datetimeoffset]::Parse($backup.marker_acknowledged_utc)).TotalSeconds,3)
        recovery_seconds=[math]::Round(($accepted-$IncidentUtc).TotalSeconds,3)
        elapsed_ms=$watch.ElapsedMilliseconds
        note='Synthetic committed marker acknowledgement is not an exact PostgreSQL commit timestamp.'
    }
    $gates.recovery_evidence='PASS'
} catch {
    $failure=$_.Exception.Message
    if($gates[$active] -eq 'NOT_RUN'){$gates[$active]='FAIL'}
} finally {
    $watch.Stop()
    $allPassed=@($gates.Values | Where-Object {$_ -ne 'PASS'}).Count -eq 0
    $report=[ordered]@{format='cloud-dr-lab-execution-evidence-v1';run_id=$runId
        generated_utc=([datetimeoffset]::UtcNow).ToString('o');started_utc=$started.ToString('o')
        elapsed_ms=$watch.ElapsedMilliseconds;archive_id=$archiveId
        result=$(if($allPassed){'PASS'}else{'FAIL_OR_INCOMPLETE'});gates=$gates
        measurement=$(if($allPassed){$measurement}else{$null})
        failure_reason=$(if($failure){'Gate failed; inspect local sanitized diagnostic'}else{$null})
        provenance='Derived from subprocess exit status and independent SQL assertions; not externally supplied PASS values.'}
    $reportFile=Join-Path $evidenceRoot "$runId.evidence.json"
    [IO.File]::WriteAllText($reportFile,($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(-not $allPassed){throw "Recovery rejected at $active; evidence=$reportFile"}
    [pscustomobject]@{status='PASS';evidence=$reportFile;archive_id=$archiveId}
}
