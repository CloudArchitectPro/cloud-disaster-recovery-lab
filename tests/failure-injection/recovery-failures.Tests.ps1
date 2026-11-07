# Opt-in executable Pester negative tests. NEVER run without isolated Phase 2 target.
# All scenarios must fail before restoration, except corrupt plaintext restore test
# which requires a separately approved disposable target.
BeforeAll {
    if($env:CLOUD_DR_PHASE2_NEGATIVE_TESTS -cne 'I_APPROVE_DISPOSABLE_PHASE2_ONLY'){
        throw 'STOP: negative tests require explicit disposable-lab opt-in'
    }
    $root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $restore=Join-Path $root 'scripts/powershell/Restore-LabDatabase.ps1'
    $fixture=$env:CLOUD_DR_PHASE2_FIXTURE_DIRECTORY
    if(-not $fixture -or -not (Test-Path -LiteralPath $fixture -PathType Container)){throw 'Missing private fixture directory'}
    $archive=Join-Path $fixture 'approved.dump.age'
    $manifest=Join-Path $fixture 'approved.manifest.json'
    $signature=Join-Path $fixture 'approved.manifest.sig'
    $verifyKey=Join-Path $fixture 'trusted-public.pem'
    $identity=Join-Path $fixture 'age-identity.txt'
    $wrongIdentity=Join-Path $fixture 'wrong-age-identity.txt'
    $badSignature=Join-Path $fixture 'bad.manifest.sig'
    $badArchive=Join-Path $fixture 'tampered.dump.age'
    $tempDir=Join-Path $fixture 'private-temp'
    $expectedId=$env:CLOUD_DR_PHASE2_APPROVED_ARCHIVE_ID
    if(-not $expectedId){throw 'Missing approved archive ID'}
    $minimum=[datetimeoffset]::UtcNow.AddHours(-24)
    $base=@{EncryptedArchive=$archive;ManifestPath=$manifest;SignaturePath=$signature
      TrustedVerificationPublicKey=$verifyKey;AgeIdentity=$identity;RestrictedTempDirectory=$tempDir
      ExpectedArchiveId=$expectedId;MinimumBackupUtc=$minimum;MaximumAgeHours=24}
}
Describe 'Phase 2 negative recovery gates' {
    It 'rejects invalid detached signatures' {
        $args=$base.Clone();$args.SignaturePath=$badSignature
        { & $restore @args } | Should -Throw
    }
    It 'rejects modified encrypted archives' {
        $args=$base.Clone();$args.EncryptedArchive=$badArchive
        { & $restore @args } | Should -Throw
    }
    It 'rejects an unapproved archive ID' {
        $args=$base.Clone();$args.ExpectedArchiveId=[guid]::NewGuid().ToString('D')
        { & $restore @args } | Should -Throw
    }
    It 'rejects an incorrect Compose project' {
        # The fixture must provide a Compose configuration that fails the fixed project allowlist.
        # No execution of restore is permitted for this scenario.
        . (Join-Path $root 'scripts/powershell/Lab-Process.ps1')
        { Assert-LabComposeService (Join-Path $root 'infrastructure/docker/compose.yaml') 'cloud-dr-phase2-validation' 'restore' 'cloud-dr-phase2-validation_phase2_restore_data' } | Should -Throw
    }
    It 'rejects wrong age identities' {
        $args=$base.Clone();$args.AgeIdentity=$wrongIdentity
        { & $restore @args } | Should -Throw
    }
    It 'rejects nonempty recovery targets' {
        # This test is meaningful only after the isolated target is intentionally populated.
        # Never seed the Phase 1 recovery database for this test.
        . (Join-Path $root 'scripts/powershell/Lab-Process.ps1')
        { Assert-LabTargetPreflight (Join-Path $root 'infrastructure/docker/compose.phase2.yaml') } | Should -Throw
    }
    It 'rejects a pg_restore failure and does not report success' {
        # Fixture: valid signed+encrypted pg_dump custom archive whose TOC is readable,
        # but contains a deterministic restore-time SQL failure. This fixture must be
        # independently constructed and approved before test execution.
        $args=$base.Clone()
        $args.EncryptedArchive=Join-Path $fixture 'restore-fails.dump.age'
        $args.ManifestPath=Join-Path $fixture 'restore-fails.manifest.json'
        $args.SignaturePath=Join-Path $fixture 'restore-fails.manifest.sig'
        $args.ExpectedArchiveId=$env:CLOUD_DR_PHASE2_FAILED_RESTORE_ARCHIVE_ID
        if(-not $args.ExpectedArchiveId){throw 'Missing approved failed-restore fixture ID'}
        { & $restore @args } | Should -Throw
    }
}
