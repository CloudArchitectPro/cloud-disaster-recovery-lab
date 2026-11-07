# Cloud Disaster Recovery Lab — Phase 2 static-hardening review

**Scope:** Review of all 19 original Phase 2 proposed files, plus two new draft files. **No PowerShell, SQL, Docker, PostgreSQL, or recovery scripts were executed.** Static inspection and archive checks only.

## Baseline preservation

- Original hardened Phase 1: 29 files; each file compared by SHA-256 and retained byte-for-byte.
- Original Phase 2 draft: 19 files.
- Revised Phase 2 draft: 21 files (7 revised, 12 unchanged, 2 new).
- Total repository: 50 files.
- No GitHub operations or production access. Existing Docker volumes were not accessed.

## All 19 original Phase 2 files reviewed

| File | Review disposition | Finding/action |
| --- | --- | --- |
| `infrastructure/docker/compose.phase2.yaml` | Revised | Requires caller-supplied immutable image digest via `POSTGRES17_IMAGE`; no fallback mutable tag |
| `scripts/sql/phase2-source-provision.sql` | Revised | Explicit atomic migration/role creation and no-change tenant policy guarantee; still non-idempotent |
| `scripts/sql/phase2-target-roles.sql` | Revised | Clarified transactional NOLOGIN role creation; explicit `lab_marker` parity |
| `scripts/powershell/Lab-Process.ps1` | Revised | Added timeouts, asynchronous stdout/stderr draining, binary-stream cancellation cleanup; not runtime tested |
| `scripts/powershell/Backup-LabDatabase.ps1` | Revised | Signed manifest binds exact filename; rejects artifact dir inside repository; requires protected ACL |
| `scripts/powershell/Restore-LabDatabase.ps1` | Revised | Explicit signed archive ID, freshness window, filename binding, protected temp directory; no auto-reset |
| `scripts/powershell/Test-LabRecovery.ps1` | Revised | Versioned expectations for counts and tenant visibility |
| `scripts/powershell/Measure-LabRecovery.ps1` | Reviewed unchanged | Synthetic marker timestamp is a proxy; no precise commit timestamp |
| `scripts/powershell/Write-LabGateEvidence.ps1` | Reviewed unchanged | **NOT APPROVED for final evidence**: accepts caller-supplied PASS statuses |
| `scripts/powershell/README-PHASE2.md` | Reviewed unchanged | Existing command shapes are incomplete after new required parameters; must update before execution |
| `config/phase2.env.example` | Reviewed unchanged | No secrets; add digest/freshness guidance before execution |
| `docs/PHASE2-IMPLEMENTATION.md` | Reviewed unchanged | Design correct in principle; update with revised image/ACL/gate policy |
| `docs/KEY-MANAGEMENT.md` | Reviewed unchanged | No keys bundled; key custody depends on unverified Windows ACL and BitLocker |
| `docs/RECOVERY-EVIDENCE.md` | Reviewed unchanged | Separates marker proxy from exact commit timestamp |
| `docs/PHASE2-FAILURE-MATRIX.md` | Reviewed unchanged | Failure scenarios documented, not executed |
| `tests/integration/backup-restore.Tests.ps1` | Reviewed unchanged | Only static contract tests, not an actual integration test |
| `tests/security/rls-recovery.Tests.ps1` | Reviewed unchanged | Static checks, not runtime RLS validation |
| `tests/failure-injection/recovery-failures.Tests.ps1` | Reviewed unchanged | Static destructive-command check, not fault injection |
| `docs/PHASE2-REVIEW.md` | Reviewed unchanged | Earlier design audit retained as historical review; this report supersedes its status |

## Two new files

| File | Purpose |
| --- | --- |
| `config/synthetic-expectations.v1.json` | Versioned, synthetic count/role/tenant expectation manifest; future source schema evolution must increment version |
| `scripts/powershell/Invoke-LabRecoveryReview.ps1` | Gate orchestration skeleton derives early gates from subprocess outcomes, then **deliberately stops** rather than fabricating independent G4/G5/G6/G7/G8 PASS results |

## Security review by requested topic

1. **Native processes:** `Invoke-LabNative` now drains both redirected streams asynchronously and enforces a timeout. Binary producer/consumer has bounded wait and process cleanup. Still unverified under Windows PowerShell 7; process-tree cleanup, streaming cancellation, `CopyToAsync` behavior, and binary `docker compose exec` must be tested.
2. **PostgreSQL 17:** Source backup role has explicit SELECT grants and RLS policies; `pg_dump -Fc --enable-row-security` is proposed. The original Phase 1 SQL is untouched. Target provisioning includes all referenced cluster-global roles, but privilege restoration, `COPY`, sequence ACLs, and the precise RLS dump/restore path remain unverified.
3. **Eight gates:** Draft orchestrator records observed subprocess outcomes for backup/encryption/signature and **fails closed at decryption/restore** because distinct machine-verifiable gate attestations are not implemented. Full G1–G8 orchestration is NOT complete.
4. **Evidence provenance:** `Write-LabGateEvidence.ps1` still accepts caller-provided statuses and must not be used to assert recovery success. New orchestrator cannot produce overall PASS. A future design must capture authenticated per-gate evidence from processes and assertions.
5. **Fail closed:** Signed archive ID, filename, digest, signature, freshness, Compose project, service and volume checks are present. Incorrect signing key, wrong decryption identity, nonempty target and unexpected project must be tested at runtime. No volume deletion path exists.
6. **Replay:** Minimum allowed backup time, maximum age and exact expected archive ID restrict replay, but are not a durable monotonic anti-rollback store. A legitimate older signed archive can still be replayed if an operator authorizes it.
7. **Windows:** Requires pre-existing artifact and temporary directories with inheritance-disabled ACLs. Does **not** yet validate effective ACEs, BitLocker status, symbolic-link/reparse-point safety, disk exhaustion, or crash persistence. Private key custody remains external.
8. **Reproducibility:** Phase 2 image now requires an immutable `postgres:17-bookworm@sha256:...` reference from a separately verified registry digest. No digest was invented. The image reference must be set before Compose config validation.

## Proposed validation commands — documentation only; NOT EXECUTED

One at a time in Windows PowerShell 7 after separate approval:

```powershell
$PSVersionTable.PSVersion
docker compose -f infrastructure/docker/compose.yaml config --quiet
# Set POSTGRES17_IMAGE to a separately verified immutable digest first.
docker compose -f infrastructure/docker/compose.phase2.yaml config --quiet
docker volume ls --filter "name=cloud-dr-lab"
age --version
openssl version
pg_restore --version
```

Further proposed read-only checks: inspect `docker compose config --format json` for expected project, service and volume names; inspect SQL role metadata; verify private key file ACLs; validate the signed manifest format and freshness constraints. None have been run.

## Acceptance gate design and blocking findings

| Gate | Intended evidence | Draft status |
| --- | --- | --- |
| G1 backup | `pg_dump` exit, committed marker, archive exists | Proposed, not executed |
| G2 encryption | age exit and encrypted file | Proposed, not executed |
| G3 manifest authentication | Ed25519 verify, SHA-256/size, freshness, approved ID | Proposed, not executed |
| G4 decryption | age exit, plaintext archive integrity | **Blocked: independent attestation absent** |
| G5 restoration | target preflight, `pg_restore` exit, transactional rollback on failure | **Blocked: independent attestation absent** |
| G6 data | marker, versioned counts, constraints, indexes, sequences | Proposed, not executed |
| G7 security | RLS/roles/memberships, positive and negative role tests | Proposed, not executed |
| G8 recovery evidence | provenance-bound gate results, timestamps, RPO/RTO | **Blocked: no trusted end-to-end evidence writer** |

### Unresolved risk register

| ID | Severity | Risk | Required resolution |
| --- | --- | --- | --- |
| R01 | Critical | G4–G8 independent gate evidence and orchestration incomplete | Implement verified structured gate attestations and fail-closed orchestrator |
| R02 | High | Native PowerShell binary stream and process timeout behavior untested | Windows PowerShell 7 isolated tests, including forced failures and cancellation |
| R03 | High | Source migration is non-idempotent and introduces LOGIN roles | Explicit source identity, role collision, privilege and membership preflight |
| R04 | High | PostgreSQL `pg_dump -Fc --enable-row-security` and restore ACL compatibility untested | Synthetic PostgreSQL 17 runtime checks and restore-policy comparison |
| R05 | High | Temporary plaintext file ACLs and crash cleanup incomplete | Secure temporary storage, ACL/BitLocker checks, crash-recovery cleanup design |
| R06 | High | Caller-supplied PASS evidence script still present | Deprecate/replace before runtime acceptance |
| R07 | Medium | Signed-archive replay possible within approved freshness window | Trusted monotonic backup checkpoint or explicitly documented manual anti-rollback approval |
| R08 | Medium | Immutable PostgreSQL digest not resolved | Verify and pin digest for intended architecture; no placeholder in executable release |
| R09 | Medium | Synthetic expectation coverage incomplete | Bind policy/grant/index/sequence/value checks to versioned manifest |
| R10 | Medium | No runtime negative/fault-injection tests | Execute only in separately approved disposable Phase 2 environment |
| R11 | Medium | Native process stdout may contain sensitive error data | Sanitize structured logs; do not print environment or key material |
| R12 | Medium | Manual source/target provisioning steps not yet safely automated | Add read-only identity preflight, transactional provisioning, explicit confirmation |
| R13 | Medium | Source backup role LOGIN authentication relies on container-local trust | Document host-Docker privilege boundary; never reuse for production |
| R14 | Low | Existing documentation references old parameter shapes | Update before any execution approval |

## Review decision

**Static hardening draft only; NOT execution-ready.** The package preserves Phase 1 exactly, adds fail-closed safeguards and versioned expectations, and records blocking gaps instead of claiming recovery validation. No scripts, SQL, containers, GitHub operations, or volumes were touched.
