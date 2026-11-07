# Phase 2 backup. REVIEW ONLY; never executed.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Recipient,
      [Parameter(Mandatory)][string]$SigningPrivateKey,
      [Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Lab-Process.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$compose=Join-Path $root 'infrastructure/docker/compose.yaml'
Assert-LabSourcePreflight $compose
if($Recipient -notmatch '^age1[023456789acdefghjklmnpqrstuvwxyz]{20,}$'){throw 'Invalid age recipient'}
$key=Assert-LabSecurePath $SigningPrivateKey -RequirePrivateAcl
$dir=Assert-LabSecurePath $ArtifactDirectory -Directory -RequirePrivateAcl
if($dir -eq $root -or $dir.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Artifacts cannot be stored in repository'}
$id=[guid]::NewGuid().ToString('D')
$encrypted=Join-Path $dir "$id.dump.age"; $manifest=Join-Path $dir "$id.manifest.json"; $sig=Join-Path $dir "$id.manifest.sig"
$watch=[Diagnostics.Stopwatch]::StartNew()
try {
    # G1: marker commit acknowledgement precedes consistent pg_dump MVCC snapshot.
    $markerSql="INSERT INTO lab_dr.recovery_markers(marker_id) VALUES ('$id') RETURNING marker_id;"
    $marker=(Invoke-LabSql $compose 'source' $markerSql 'lab_marker')
    if($marker -cne $id){throw 'Committed marker acknowledgement mismatch'}
    $ack=[datetimeoffset]::UtcNow
    # G1/G2 are individually attested by the producer/consumer exit codes.
    $pipe=Invoke-LabBinaryPipeline -Producer 'docker' -ProducerArgs @('compose','-f',$compose,'exec','-T','source','pg_dump','-U','lab_backup','-d','labdb','-Fc','--enable-row-security','--schema=lab','--schema=lab_dr','--no-password') -Consumer 'age' -ConsumerArgs @('-r',$Recipient,'-o',$encrypted) -TimeoutSeconds 300
    if($pipe.ProducerExit -ne 0 -or $pipe.ConsumerExit -ne 0){throw 'Dump/encryption subprocess failed'}
    $f=Get-Item -LiteralPath $encrypted -ErrorAction Stop
    if($f.Length -lt 100){throw 'Encrypted archive too small'}
    $manifestBody=[ordered]@{format='cloud-dr-lab-manifest-v2';archive_id=$id;encrypted_filename=$f.Name
        marker_id=$id;marker_acknowledged_utc=$ack.ToString('o');created_utc=([datetimeoffset]::UtcNow).ToString('o')
        postgres_major=17;archive_format='pg_dump-custom';expectations_version='synthetic-seed-v1'
        scope=@('lab','lab_dr');encrypted_bytes=$f.Length
        encrypted_sha256=(Get-FileHash -LiteralPath $encrypted -Algorithm SHA256).Hash.ToLowerInvariant()}
    [IO.File]::WriteAllText($manifest,($manifestBody | ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false))
    $null=Invoke-LabProcess openssl @('pkeyutl','-sign','-rawin','-inkey',$key,'-in',$manifest,'-out',$sig)
    if((Get-Item -LiteralPath $sig).Length -lt 32){throw 'Detached signature missing'}
    $watch.Stop()
    [pscustomobject]@{archive_id=$id;encrypted_archive=$encrypted;manifest=$manifest;signature=$sig
        marker_acknowledged_utc=$ack.ToString('o');dump_exit=$pipe.ProducerExit;age_exit=$pipe.ConsumerExit
        signing_exit=0;elapsed_ms=$watch.ElapsedMilliseconds}
} catch {
    foreach($path in @($encrypted,$manifest,$sig)) {if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
    throw
}
