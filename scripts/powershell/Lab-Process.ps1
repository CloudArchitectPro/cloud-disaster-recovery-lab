# Phase 2 native process and safety primitives. REVIEW ONLY; never executed.
Set-StrictMode -Version Latest
function Invoke-LabProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$File,[string[]]$Arguments=@(),
          [int]$TimeoutSeconds=120,[string]$StdinFile='', [string]$StdoutFile='')
    if ($TimeoutSeconds -lt 1) { throw 'Timeout must be positive' }
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$File; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.RedirectStandardInput=!!$StdinFile
    foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add($a) }
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$psi
    $sink=$null; $input=$null
    try {
        if (-not $p.Start()) { throw 'Process could not start' }
        $stderr=$p.StandardError.ReadToEndAsync()
        if ($StdoutFile) {
            $sink=[IO.File]::Open($StdoutFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $output=$p.StandardOutput.BaseStream.CopyToAsync($sink)
        } else { $output=$p.StandardOutput.ReadToEndAsync() }
        if ($StdinFile) {
            $input=[IO.File]::OpenRead($StdinFile)
            $copy=$input.CopyToAsync($p.StandardInput.BaseStream)
            if (-not $copy.Wait($TimeoutSeconds*1000)) { throw 'Input stream timeout' }
            $p.StandardInput.Close()
        }
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) { throw 'Process timeout' }
        if (-not $output.Wait($TimeoutSeconds*1000)) { throw 'Output stream timeout' }
        if (-not $stderr.Wait($TimeoutSeconds*1000)) { throw 'Error stream timeout' }
        if ($p.ExitCode -ne 0) { throw "Process failed: $File (exit $($p.ExitCode))" }
        if ($StdoutFile) { return [pscustomobject]@{ ExitCode=0; Output=''; File=$StdoutFile } }
        return [pscustomobject]@{ ExitCode=0; Output=$output.Result.Trim(); File='' }
    } finally {
        if ($p -and -not $p.HasExited) { try { $p.Kill($true) } catch {} }
        if ($sink) { $sink.Dispose() }; if ($input) { $input.Dispose() }; $p.Dispose()
    }
}
function Invoke-LabBinaryPipeline {
    [CmdletBinding()]
    param([string]$Producer,[string[]]$ProducerArgs,[string]$Consumer,[string[]]$ConsumerArgs,
          [int]$TimeoutSeconds=300)
    $a=$null; $b=$null; $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $bp=[Diagnostics.ProcessStartInfo]::new($Consumer); $bp.UseShellExecute=$false
        $bp.RedirectStandardInput=$true; $bp.RedirectStandardError=$true; $bp.RedirectStandardOutput=$true
        foreach($arg in $ConsumerArgs){[void]$bp.ArgumentList.Add($arg)}
        $b=[Diagnostics.Process]::Start($bp)
        $be=$b.StandardError.ReadToEndAsync(); $bo=$b.StandardOutput.ReadToEndAsync()
        $ap=[Diagnostics.ProcessStartInfo]::new($Producer); $ap.UseShellExecute=$false
        $ap.RedirectStandardOutput=$true; $ap.RedirectStandardError=$true
        foreach($arg in $ProducerArgs){[void]$ap.ArgumentList.Add($arg)}
        $a=[Diagnostics.Process]::Start($ap)
        $ae=$a.StandardError.ReadToEndAsync()
        $copy=$a.StandardOutput.BaseStream.CopyToAsync($b.StandardInput.BaseStream)
        while (-not $copy.Wait(250)) { if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {throw 'Pipeline copy timeout'} }
        $b.StandardInput.Close()
        foreach($p in @($a,$b)) {
            $left=[math]::Max(1,[int](($TimeoutSeconds-$watch.Elapsed.TotalSeconds)*1000))
            if(-not $p.WaitForExit($left)){throw 'Pipeline process timeout'}
        }
        foreach($t in @($ae,$be,$bo)){if(-not $t.Wait(1000)){throw 'Pipeline stream timeout'}}
        if($a.ExitCode -ne 0 -or $b.ExitCode -ne 0){throw "Pipeline exit codes: producer=$($a.ExitCode), consumer=$($b.ExitCode)"}
        return [pscustomobject]@{ ProducerExit=0; ConsumerExit=0; ElapsedMs=$watch.ElapsedMilliseconds }
    } finally {
        foreach($p in @($a,$b)) {if($p){if(-not $p.HasExited){try{$p.Kill($true)}catch{}};$p.Dispose()}}
    }
}
function Assert-LabSecurePath {
    param([string]$Path,[switch]$Directory,[switch]$RequirePrivateAcl)
    $full=[IO.Path]::GetFullPath($Path)
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'STOP: reparse-point path'}
    $parent=[IO.Path]::GetDirectoryName($full)
    while($parent){
        $ancestor=Get-Item -LiteralPath $parent -Force
        if($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'STOP: reparse-point ancestor'}
        $next=[IO.Path]::GetDirectoryName($parent);if($next -eq $parent){break};$parent=$next
    }
    if($Directory -and -not $item.PSIsContainer){throw 'Expected directory'}
    if(-not $Directory -and $item.PSIsContainer){throw 'Expected file'}
    if($RequirePrivateAcl){
        if(-not $IsWindows){throw 'Private ACL gate requires Windows'}
        $acl=Get-Acl -LiteralPath $full
        if(-not $acl.AreAccessRulesProtected){throw 'STOP: inherited ACL'}
        $me=[Security.Principal.WindowsIdentity]::GetCurrent().User
        foreach($rule in $acl.Access){
            if($rule.AccessControlType -ne 'Allow'){continue}
            $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if($sid -notin @($me.Value,'S-1-5-18','S-1-5-32-544')){throw 'STOP: unexpected allow ACE'}
        }
    }
    return $full
}
function Assert-LabComposeService {
    param([string]$Compose,[string]$Project,[string]$Service,[string]$Volume)
    $cfg=(Invoke-LabProcess docker @('compose','-f',$Compose,'config','--format','json')).Output | ConvertFrom-Json
    if($cfg.name -cne $Project -or -not $cfg.services.PSObject.Properties[$Service]){throw 'STOP: Compose identity mismatch'}
    if($cfg.services.$Service.ports){throw 'STOP: published database port'}
    $ids=(Invoke-LabProcess docker @('compose','-f',$Compose,'ps','-q',$Service)).Output -split "`n" | Where-Object {$_}
    if(@($ids).Count -ne 1){throw 'STOP: expected exactly one existing service container'}
    $container=@(((Invoke-LabProcess docker @('inspect',$ids[0])).Output | ConvertFrom-Json))[0]
    if($container.Config.Labels.'com.docker.compose.project' -cne $Project -or
       $container.Config.Labels.'com.docker.compose.service' -cne $Service -or -not $container.State.Running){throw 'STOP: container identity mismatch'}
    $volumes=@($container.Mounts | Where-Object {$_.Type -eq 'volume'} | ForEach-Object {$_.Name})
    if($Volume -notin $volumes){throw 'STOP: expected volume missing'}
    if($Project -eq 'cloud-dr-phase2-validation' -and @($volumes | Where-Object {$_ -in @('cloud-dr-lab_source_data','cloud-dr-lab_recovery_data')}).Count){throw 'STOP: Phase 1 volume mounted'}
    return $container
}
function Invoke-LabSql {
    param([string]$Compose,[string]$Service,[string]$Sql,[string]$Role='lab_owner')
    return (Invoke-LabProcess docker @('compose','-f',$Compose,'exec','-T',$Service,'psql','-X','-U',$Role,'-d','labdb','-At','-v','ON_ERROR_STOP=1','-c',$Sql) -TimeoutSeconds 60).Output
}
function Assert-LabSourcePreflight {
    param([string]$Compose)
    $null=Assert-LabComposeService $Compose 'cloud-dr-lab' 'source' 'cloud-dr-lab_source_data'
    $sql=@'
SELECT CASE WHEN current_database()='labdb'
 AND (SELECT count(*) FROM pg_namespace WHERE nspname='lab')=1
 AND (SELECT count(*) FROM pg_namespace WHERE nspname='lab_dr')=1
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN ('lab_backup','lab_marker') AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication)=2
 AND (SELECT count(*) FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname IN ('lab_backup','lab_marker'))=0
 AND (SELECT count(*) FROM pg_class WHERE oid IN ('lab.organizations'::regclass,'lab.assets'::regclass,'lab.recovery_events'::regclass) AND relrowsecurity AND relforcerowsecurity)=3
 THEN 'READY' ELSE 'REJECT' END;
'@
    if((Invoke-LabSql $Compose 'source' $sql) -cne 'READY'){throw 'STOP: source roles or RLS preflight failed'}
}
function Assert-LabTargetPreflight {
    param([string]$Compose)
    $null=Assert-LabComposeService $Compose 'cloud-dr-phase2-validation' 'restore' 'cloud-dr-phase2-validation_phase2_restore_data'
    $sql=@'
SELECT CASE WHEN current_database()='labdb'
 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN ('lab','lab_dr'))=0
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN ('lab_tenant_north','lab_tenant_south','lab_anonymous','lab_backup','lab_marker') AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication)=5
 AND (SELECT count(*) FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname IN ('lab_tenant_north','lab_tenant_south','lab_anonymous','lab_backup','lab_marker'))=0
 THEN 'READY' ELSE 'REJECT' END;
'@
    if((Invoke-LabSql $Compose 'restore' $sql) -cne 'READY'){throw 'STOP: target not empty or roles incorrect'}
}
function Assert-LabImageDigest {
    param([string]$Compose)
    if($env:POSTGRES17_IMAGE -notmatch '^postgres:17-bookworm@sha256:[0-9a-f]{64}$'){throw 'STOP: verified immutable PostgreSQL digest required'}
    $cfg=(Invoke-LabProcess docker @('compose','-f',$Compose,'config','--format','json')).Output | ConvertFrom-Json
    if($cfg.services.restore.image -cne $env:POSTGRES17_IMAGE){throw 'STOP: Compose image mismatch'}
    $container=Assert-LabComposeService $Compose 'cloud-dr-phase2-validation' 'restore' 'cloud-dr-phase2-validation_phase2_restore_data'
    $image=@(((Invoke-LabProcess docker @('image','inspect',$env:POSTGRES17_IMAGE)).Output | ConvertFrom-Json))[0]
    if($container.Image -cne $image.Id){throw 'STOP: running container image ID differs from approved digest image'}
    if(@($image.RepoDigests | Where-Object {$_ -like ('*@sha256:' + ($env:POSTGRES17_IMAGE -split '@sha256:')[-1])}).Count -lt 1){throw 'STOP: local image does not advertise approved RepoDigest'}
    # The digest must ALSO be independently verified against a trusted registry/source before setting it.
}
