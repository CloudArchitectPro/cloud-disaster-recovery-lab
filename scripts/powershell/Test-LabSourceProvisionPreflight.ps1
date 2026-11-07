# Read-only identity and collision preflight BEFORE separately approved additive migration.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Lab-Process.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$compose=Join-Path $root 'infrastructure/docker/compose.yaml'
$null=Assert-LabComposeService $compose 'cloud-dr-lab' 'source' 'cloud-dr-lab_source_data'
$sql=@'
SELECT CASE WHEN current_database()='labdb'
 AND (SELECT count(*) FROM pg_namespace WHERE nspname='lab')=1
 AND (SELECT count(*) FROM pg_namespace WHERE nspname='lab_dr')=0
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN ('lab_backup','lab_marker'))=0
 AND (SELECT count(*) FROM pg_class WHERE oid IN ('lab.organizations'::regclass,'lab.assets'::regclass,'lab.recovery_events'::regclass) AND relrowsecurity AND relforcerowsecurity)=3
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN ('lab_tenant_north','lab_tenant_south','lab_anonymous') AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls)=3
 THEN 'READY' ELSE 'REJECT' END;
'@
if((Invoke-LabSql $compose 'source' $sql) -cne 'READY'){throw 'STOP: source identity or migration collision detected'}
[pscustomobject]@{ready=$true;project='cloud-dr-lab';database='labdb';migration='NOT_APPLIED'}
