# Phase 2 implementation review — STOP BEFORE EXECUTION

**Status:** Proposed source files only. No PowerShell scripts, SQL, Docker, PostgreSQL, age, OpenSSL, Pester, or GitHub workflows were executed. No GitHub or production infrastructure was accessed.

## Baseline preservation

The Phase 1 source archive is `cloud-disaster-recovery-lab-phase1-hardened-review.zip` with SHA-256 `a45bebe26be9d9f4c70e1072c46131967d9d38117a2a3802819d024dad50386a`. Its 29 files are preserved **byte-for-byte** in this proposed review tree. All Phase 2 additions are separate files. The two local Phase 1 Docker volumes have not been accessed.

## File-by-file changes

**Existing Phase 1 files changed:** None.

| New file | Purpose / security considerations |
| --- | --- |
| `infrastructure/docker/compose.phase2.yaml` | Dedicated `cloud-dr-phase2-validation` project, internal network, new named volume; no published ports |
| `scripts/sql/phase2-source-provision.sql` | Additive synthetic marker schema; source `lab_backup` and `lab_marker` least-privilege roles; RLS SELECT policies; no edits to tenant policies |
| `scripts/sql/phase2-target-roles.sql` | Deterministic NOLOGIN target roles, including `lab_marker`; no memberships; no global BYPASSRLS |
| `scripts/powershell/Lab-Process.ps1` | Native process execution and project/volume allowlist; no auto-start or volume deletion |
| `scripts/powershell/Backup-LabDatabase.ps1` | Committed marker, `pg_dump -Fc --enable-row-security`, binary-stream age encryption, signed manifest |
| `scripts/powershell/Restore-LabDatabase.ps1` | Detached-signature and digest verification; target and role preflight; age decrypt; `pg_restore` fail-fast |
| `scripts/powershell/Test-LabRecovery.ps1` | Synthetic counts, marker, schema, RLS and negative access assertions |
| `scripts/powershell/Measure-LabRecovery.ps1` | Recovery-point marker proxy and elapsed-time calculation |
| `scripts/powershell/Write-LabGateEvidence.ps1` | Eight explicit gates; no PASS if any missing/failed (caller-supplied evidence is not independently authenticated) |
| `scripts/powershell/README-PHASE2.md` | Windows prerequisites and proposed command shapes |
| `config/phase2.env.example` | Generic placeholders, no secrets |
| `docs/PHASE2-IMPLEMENTATION.md` | Architecture, snapshot/role design, execution stages, gates |
| `docs/KEY-MANAGEMENT.md` | age X25519, Ed25519 signatures, Windows key custody |
| `docs/RECOVERY-EVIDENCE.md` | Evidence schema, marker proxy, RPO/RTO boundaries |
| `docs/PHASE2-FAILURE-MATRIX.md` | Fault injection and fail-closed outcomes |
| `tests/integration/backup-restore.Tests.ps1` | Pester static isolation contract; **not** end-to-end integration |
| `tests/security/rls-recovery.Tests.ps1` | Pester static role/policy checks; **not** runtime RLS validation |
| `tests/failure-injection/recovery-failures.Tests.ps1` | Pester static destructive-command scan; **not** actual failure injection |
| `docs/PHASE2-REVIEW.md` | This review and execution prerequisites |

## Trust boundaries and security review

- Source uses the existing `cloud-dr-lab` project and existing `source` volume. Source SQL is **additive** and requires separate approval before any run.
- `lab_backup` is LOGIN but not superuser/BYPASSRLS; SELECT-only with explicit RLS policies covering synthetic rows. `lab_marker` is LOGIN with INSERT/SELECT only on synthetic marker table. Neither receives memberships.
- The Docker image's local Unix socket trust allows a privileged Docker host user to impersonate DB roles; this is a **lab-only** boundary, not production authentication.
- Target roles are NOLOGIN, non-superuser, non-BYPASSRLS and no memberships. `lab_owner` performs restore as a lab-only privileged actor.
- Existing tenant policies remain unchanged. The new `lab_dr` marker table has its own RLS and FORCE RLS.
- Artifact manifest is Ed25519-signed; its SHA-256 refers to encrypted bytes. Trusted verification public key must be pinned outside the untrusted artifact directory.
- age private identity and signing private key are never bundled. Windows key paths must remain outside repository and artifact directory.
- Target preflight verifies Compose project/service/volume and absence of existing application schemas. **No automatic deletion of containers or volumes**.
- Plaintext exists briefly in a Windows temporary file during restore. Delete-on-exit is not forensic erasure. NTFS ACL and BitLocker protections require validation.
- Native process stderr is not logged by default in binary pipeline; this reduces accidental leakage but limits diagnostics. Failure paths need real testing.

## Snapshot consistency and RPO

`pg_dump` obtains a transactionally consistent MVCC snapshot. The unique marker is inserted and committed in a separate completed `psql` call **before** dump starts. The signed manifest stores marker UUID and acknowledgement UTC recorded after commit. Restore validation checks marker UUID.

The marker acknowledgement time is **not** an exact PostgreSQL commit timestamp. With no intervening writes it supports a controlled synthetic recovery-point experiment; it does not prove the precise last committed transaction across the database. Exact commit timestamps would require additional database configuration/verification, which is not part of this draft.

## Acceptance gates

1. G1 backup: committed marker, successful nonempty `pg_dump` archive.
2. G2 encryption: age succeeds, nonempty encrypted artifact.
3. G3 authentication: valid Ed25519 signature and encrypted size/hash match.
4. G4 decryption: age succeeds and creates expected plaintext archive.
5. G5 restore: target identity/empty-schema/roles verified; archive inspected; single-transaction `pg_restore` succeeds.
6. G6 data: exact synthetic counts/marker/constraints/indexes/sequences.
7. G7 security: roles, memberships, RLS/FORCE, tenant isolation, anonymous and write denials.
8. G8 evidence: sanitized results and timestamped measurement; no missing gate.

**Integration gap:** The proposed individual scripts are not yet wired into an independently authenticated end-to-end orchestrator. `Write-LabGateEvidence.ps1` validates the presence and values of caller-supplied gate statuses but cannot attest that a test actually ran. No overall Phase 2 PASS is justified until the gate provenance and orchestration are implemented and executed.

## Prerequisites before any execution approval

- Windows PowerShell 7.4+, Docker Desktop with Compose, PostgreSQL 17 local image.
- Local `age` and `age-keygen` executables; OpenSSL 3 Ed25519 `pkeyutl` support; PostgreSQL 17 `pg_restore` installed on Windows.
- Pester v5 only for separately approved test runs.
- Dedicated keys created and secured outside repository; trusted public key fingerprint reviewed independently.
- Verify Docker Compose JSON output and expected labels/volume names on Windows.
- Check `pg_dump --enable-row-security` successfully backs up all synthetic rows without BYPASSRLS.
- Confirm PostgreSQL cluster-global role provisioning is compatible with restored policies and ACLs.
- Review source migration impact and make a separate, restorable copy of the synthetic source before any migration.
- Confirm temporary-file ACLs, available disk space and artifact directory permissions.
- Approve each PowerShell command separately. Do not run a multi-command block unreviewed.

## Proposed validation commands (reference only; DO NOT EXECUTE YET)

From `the repository root` in PowerShell 7, **one at a time after approval**:

```powershell
$PSVersionTable.PSVersion
docker compose -f infrastructure/docker/compose.yaml config --quiet
docker compose -f infrastructure/docker/compose.phase2.yaml config --quiet
docker volume ls --filter "name=cloud-dr-lab"
age --version
openssl version
pg_restore --version
```

After a separate execution approval, source migration would be applied through an explicitly verified source container, the Phase 2 target would be started separately, and target role provisioning would occur only after confirming its empty state. Backup/restore commands require absolute paths for keys and encrypted artifacts. Never run `docker compose down -v`.

## Failure handling

All native-process failures are nonzero and block later gates. Backup failures remove newly created encrypted artifacts and manifests. Signature and digest failures block decryption. Restore preflight failures block writes. Transactional restore errors abort the restore; a failed target is retained for diagnosis and must not be reused without deliberate review. Temporary plaintext is removed in `finally`, but process termination or host crash may leave it behind; this is an unresolved risk.

## Unresolved risks / implementation defects to verify

1. **HIGH:** The scripts have not been parsed or run under Windows PowerShell 7. Native binary stream handling and Docker stdout/stderr behavior need testing.
2. **HIGH:** SQL source provisioning is not idempotent; re-running will fail. This is intentional fail-closed behavior, but an explicit preflight is needed.
3. **HIGH:** Role/ACL restoration and `pg_dump --enable-row-security` need real PostgreSQL tests, including `lab_marker` role references.
4. **HIGH:** End-to-end gate orchestration and authenticated evidence provenance are not implemented; caller-supplied gate status is not trustworthy evidence.
5. **MEDIUM:** Restore plaintext uses temporary disk storage; key and temporary file ACL hardening require validation.
6. **MEDIUM:** Signed manifest does not prevent replay of an older legitimately signed archive; recovery policy must independently enforce freshness.
7. **MEDIUM:** Marker acknowledgement is a conservative proxy, not an exact commit timestamp or general database RPO.
8. **MEDIUM:** Image tag `postgres:17-bookworm` is mutable; immutable digest pinning remains pending.
9. **MEDIUM:** Static Pester files do not exercise runtime restore or fault injection.
10. **MEDIUM:** Backup/restore scripts need robust timeouts, cancellation handling and cleanup on host crashes.
11. **MEDIUM:** The validation count checks assume the original synthetic seed dataset; added synthetic rows require a versioned expectation manifest.
12. **LOW:** Optional Cloudflare R2 and Terraform remain deferred.

## Approval boundary

This package is for **design/code review only**. No execution, GitHub repository creation, commit, push, publication, production access, or volume mutation is authorized.
