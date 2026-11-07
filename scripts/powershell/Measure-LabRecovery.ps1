# REVIEW DRAFT: computes synthetic marker proxy metrics from approved timestamps.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][datetimeoffset]$IncidentUtc,
    [Parameter(Mandatory)][datetimeoffset]$MarkerAcknowledgedUtc,
    [Parameter(Mandatory)][datetimeoffset]$RecoveryAcceptedUtc,
    [Parameter(Mandatory)][long]$RestoreAndValidationElapsedMs
)
$ErrorActionPreference = 'Stop'
if ($IncidentUtc -lt $MarkerAcknowledgedUtc) { throw 'Incident precedes marker acknowledgement' }
if ($RecoveryAcceptedUtc -lt $IncidentUtc) { throw 'Recovery accepted before incident' }
if ($RestoreAndValidationElapsedMs -lt 0) { throw 'Invalid elapsed duration' }
[ordered]@{
    status = 'MEASUREMENT_ONLY_NOT_A_RECOVERY_PASS'
    marker_age_proxy_seconds = [math]::Round(($IncidentUtc-$MarkerAcknowledgedUtc).TotalSeconds,3)
    observed_recovery_seconds = [math]::Round(($RecoveryAcceptedUtc-$IncidentUtc).TotalSeconds,3)
    restore_and_validation_elapsed_ms = $RestoreAndValidationElapsedMs
    note = 'Marker acknowledgement is after commit, not an exact database commit timestamp. RTO excludes dependencies outside defined lab acceptance.'
} | ConvertTo-Json
