# Phase 2 Windows PowerShell 7 — final implementation review (NOT EXECUTED)

This is a code-review candidate, not a validated recovery product. **Do not run commands below without a separate approval.** Keep Phase 1 containers and both original volumes intact. Source migration is additive but mutates the synthetic source; it requires its own explicit approval.

## Required tools and setup

- Windows PowerShell 7.4+, Docker Desktop and Compose, PostgreSQL 17 client `pg_restore`, `age`, OpenSSL 3 (Ed25519 `pkeyutl`), and Pester 5 for tests.
- Set `POSTGRES17_IMAGE` to a **separately verified** `postgres:17-bookworm@sha256:<64-hex>` reference. No digest is provided or invented. Verify the running container's image ID and architecture independently.
- Precreate separate Windows NTFS directories **outside the repository** for artifacts, private temporary archives, evidence and keys. Disable inherited ACEs, and allow only the current account, SYSTEM, and Administrators. Ensure BitLocker protection. Do not use junctions, symlinks, or reparse-point ancestors. ACL checking is conservative but cannot prove exclusive access by local administrators.
- Create an age X25519 identity and independent Ed25519 signing key offline. Keep signing and decryption private keys in restricted locations. Pin verification public key fingerprint independently.
- The synthetic source migration creates two LOGIN roles; Docker in-container trust remains a lab-only boundary. Target roles are NOLOGIN. Neither model is production authentication.
- Do not run restore on any nonempty target or original Phase 1 recovery volume.

## Proposed staged commands (reference only; NOT executed)

Run **one command at a time** after explicit authorization:

```powershell
$PSVersionTable.PSVersion
# Read-only source migration preflight, requires running synthetic source:
./scripts/powershell/Test-LabSourceProvisionPreflight.ps1
# Configuration checks only, after supplying verified POSTGRES17_IMAGE:
docker compose -f infrastructure/docker/compose.phase2.yaml config --quiet
```

Only after separate approval: apply `scripts/sql/phase2-source-provision.sql` to the verified source, provision the dedicated disposable target with `scripts/sql/phase2-target-roles.sql`, and start its separate Compose project. Neither step is automated by the orchestrator.

Main orchestrator parameter contract:

```powershell
# NOT TO EXECUTE UNTIL APPROVED
./scripts/powershell/Invoke-LabRecoveryReview.ps1 `
  -Recipient '<AGE_PUBLIC_RECIPIENT>' `
  -SigningPrivateKey '<ABSOLUTE_PRIVATE_SIGNING_KEY_PATH>' `
  -TrustedVerificationPublicKey '<ABSOLUTE_PINNED_PUBLIC_KEY_PATH>' `
  -AgeIdentity '<ABSOLUTE_PRIVATE_AGE_IDENTITY_PATH>' `
  -ArtifactDirectory '<PRECREATED_RESTRICTED_ARTIFACT_DIRECTORY>' `
  -RestrictedTempDirectory '<PRECREATED_RESTRICTED_TEMP_DIRECTORY>' `
  -EvidenceDirectory '<PRECREATED_RESTRICTED_EVIDENCE_DIRECTORY>' `
  -MinimumBackupUtc ([datetimeoffset]'2026-11-07T00:00:00Z') `
  -IncidentUtc ([datetimeoffset]'2026-11-07T00:00:00Z') `
  -MaximumAgeHours 24
```

**Incident timestamp must be after the marker acknowledgement**. For a meaningful RPO/RTO experiment, the incident time should be declared at a controlled point in the workflow; the current orchestrator accepts a supplied incident time and validates its ordering but does not itself simulate an incident. Do not interpret the resulting metric as a production RPO or RTO.

## Eight gates

G1 dump and committed marker, G2 age encryption, G3 signed manifest, G4 decryption/archive inspection, G5 single-transaction restore, G6 independent data assertions, G7 independent RLS/ACL/role tests, G8 evidence/timing. No caller-supplied PASS statuses. Legacy `Write-LabGateEvidence.ps1` is disabled.

## Negative tests

Pester failure-injection file requires explicit `CLOUD_DR_PHASE2_NEGATIVE_TESTS` opt-in and isolated fixtures. The failed-restore test is executable but requires an independently prepared, valid signed/encrypted custom-format fixture that fails during pg_restore; it has not been prepared or executed. Run only against the disposable Phase 2 target after verifying its identity and state. Tests for wrong keys/signatures/modified archives require independently generated fixtures.

## Recovery limitations

- No point-in-time recovery, WAL archive, offsite backup, cloud access or production claims.
- Backup is a consistent MVCC snapshot; marker acknowledgement is **not** an exact commit timestamp.
- Restore plaintext is temporarily written to NTFS. Crash cleanup, secure erasure, effective ACLs and anti-rollback state remain concerns.
- Signed manifest freshness and explicit archive ID prevent accidental stale selection but not a malicious authorized replay without a trusted monotonic checkpoint.
- No scripts, Docker commands, SQL or tests were executed to prepare this package.
