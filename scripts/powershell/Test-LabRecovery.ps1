# Independent restored database assertions; read-only except a deliberately denied UPDATE.
# REVIEW ONLY; never executed.
[CmdletBinding()]
param([Parameter(Mandatory)][guid]$ExpectedMarkerId)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Lab-Process.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$compose=Join-Path $root 'infrastructure/docker/compose.phase2.yaml'
Assert-LabImageDigest $compose
$expect=Get-Content -LiteralPath (Join-Path $root 'config/synthetic-expectations.v1.json') -Raw | ConvertFrom-Json
if($expect.version -cne 'synthetic-seed-v1'){throw 'Unexpected synthetic expectations version'}
function Scalar([string]$sql){(Invoke-LabSql $compose 'restore' $sql).Trim()}
function Check([string]$name,[string]$sql,[string]$expected){
    $actual=Scalar $sql
    if($actual -cne $expected){throw "ASSERTION_FAILED $name"}
}
function RoleScalar([string]$role,[string]$sql){
    $query="BEGIN; SET LOCAL ROLE $role; $sql ROLLBACK;"
    $lines=(Scalar $query) -split "`r?`n" | ForEach-Object {$_.Trim()}
    return @($lines | Where-Object {$_ -notin @('BEGIN','SET','ROLLBACK')})[-1]
}
function ExpectDenied([string]$role,[string]$sql){
    $query="BEGIN; SET LOCAL ROLE $role; $sql"
    $args=@('compose','-f',$compose,'exec','-T','restore','psql','-X','-U','lab_owner','-d','labdb','-At','-v','ON_ERROR_STOP=1','-c',$query)
    $psi=[Diagnostics.ProcessStartInfo]::new('docker');$psi.UseShellExecute=$false
    $psi.RedirectStandardError=$true;$psi.RedirectStandardOutput=$true
    foreach($a in $args){[void]$psi.ArgumentList.Add($a)}
    $p=[Diagnostics.Process]::Start($psi)
    try {
        $stderr=$p.StandardError.ReadToEndAsync();$stdout=$p.StandardOutput.ReadToEndAsync()
        if(-not $p.WaitForExit(60000)){throw 'Negative test timed out'}
        if(-not $stderr.Wait(2000) -or -not $stdout.Wait(2000)){throw 'Negative test stream timeout'}
        if($p.ExitCode -eq 0 -or $stderr.Result -notmatch 'permission denied'){throw "Expected PostgreSQL permission denial for $role"}
    } finally {if(-not $p.HasExited){try{$p.Kill($true)}catch{}};$p.Dispose()}
}
# G6: versioned data expectations, marker and structural assertions.
Check 'organizations' 'SELECT count(*) FROM lab.organizations' ([string]$expect.tables.'lab.organizations')
Check 'assets' 'SELECT count(*) FROM lab.assets' ([string]$expect.tables.'lab.assets')
Check 'events' 'SELECT count(*) FROM lab.recovery_events' ([string]$expect.tables.'lab.recovery_events')
Check 'marker' "SELECT count(*) FROM lab_dr.recovery_markers WHERE marker_id='$ExpectedMarkerId'" '1'
$expectedAssets=@($expect.assets.PSObject.Properties | Sort-Object Name | ForEach-Object {"$($_.Name):$($_.Value)"}) -join ','
Check 'asset-values' "SELECT string_agg(asset_code || ':' || status, ',' ORDER BY asset_code) FROM lab.assets" $expectedAssets
Check 'constraints' "SELECT count(*) FROM pg_constraint WHERE conrelid IN ('lab.organizations'::regclass,'lab.assets'::regclass,'lab.recovery_events'::regclass) AND contype IN ('p','f','u','c') AND convalidated" ([string]$expect.required_constraints)
Check 'index' "SELECT count(*) FROM pg_index WHERE indrelid='lab.recovery_events'::regclass AND indisvalid AND indexrelid='lab.recovery_events_asset_idx'::regclass" '1'
Check 'sequences' "SELECT count(*) FROM pg_sequences WHERE schemaname='lab'" '3'
# G7: metadata checks + effective restricted-role assertions.
Check 'rls-force' "SELECT count(*) FROM pg_class WHERE oid IN ('lab.organizations'::regclass,'lab.assets'::regclass,'lab.recovery_events'::regclass,'lab_dr.recovery_markers'::regclass) AND relrowsecurity AND relforcerowsecurity" '4'
Check 'required-policies' "SELECT count(*) FROM pg_policies WHERE schemaname IN ('lab','lab_dr') AND policyname IN ('org_tenant_read','asset_tenant_read','event_tenant_read','org_backup_read','asset_backup_read','event_backup_read','marker_backup_read','marker_writer_read','marker_writer_insert')" '9'
Check 'roles' "SELECT count(*) FROM pg_roles WHERE rolname IN ('lab_tenant_north','lab_tenant_south','lab_anonymous','lab_backup','lab_marker') AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication" '5'
Check 'memberships' "SELECT count(*) FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname IN ('lab_tenant_north','lab_tenant_south','lab_anonymous','lab_backup','lab_marker')" '0'
Check 'tenant-select-grants' "SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='lab' AND privilege_type='SELECT' AND grantee IN ('lab_tenant_north','lab_tenant_south')" '6'
Check 'backup-select-grants' "SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='lab' AND privilege_type='SELECT' AND grantee='lab_backup'" '3'
foreach($role in @('lab_tenant_north','lab_tenant_south')) {
    $counts=@((RoleScalar $role 'SELECT (SELECT count(*) FROM lab.organizations)::text || ''|'' || (SELECT count(*) FROM lab.assets)::text || ''|'' || (SELECT count(*) FROM lab.recovery_events)::text;'))
    if($counts[0] -cne (@($expect.tenant_counts.$role) -join '|')){throw "Tenant counts mismatch: $role"}
}
if((RoleScalar 'lab_tenant_north' "SELECT count(*) FROM lab.assets WHERE asset_code='SAMPLE-C';") -cne '0'){throw 'Cross-tenant read leak'}
ExpectDenied 'lab_anonymous' 'SELECT count(*) FROM lab.assets;'
ExpectDenied 'lab_tenant_north' "UPDATE lab.assets SET status='offline' WHERE asset_code='SAMPLE-A';"
[pscustomobject]@{data=[pscustomobject]@{verified=$true;assertions=8};security=[pscustomobject]@{verified=$true;assertions=15};marker_id=$ExpectedMarkerId.ToString('D')}
