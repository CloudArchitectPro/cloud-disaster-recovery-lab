# Phase 2 — Final focused implementation review

**Status: CODE REVIEW CANDIDATE, NOT EXECUTION-APPROVED.** All new code is unexecuted. No PowerShell, Pester, SQL, Docker, age, OpenSSL, or pg_restore commands were run. Existing Docker volumes were not accessed.

## Scope and baseline

Working baseline: 51-file static-hardened package. Original 29 Phase 1 files retained byte-for-byte. Phase 2 files were revised to implement the eight-gate workflow rather than only a planning document.

## Complete changed-file summary

| File | Changes |
| --- | --- |
| `scripts/powershell/Lab-Process.ps1` | Replaced native-process helpers; binary stdin/stdout, async drain, bounded waits, process-tree termination, Windows ACL and reparse-point checks, Compose identity/volume checks, image digest identity check, read-only source/target SQL preflight |
| `scripts/powershell/Backup-LabDatabase.ps1` | Returns structured observed dump/encryption/signing exits; committed synthetic marker; binary `pg_dump -Fc` to age; signed v2 manifest |
| `scripts/powershell/Restore-LabDatabase.ps1` | G3 signature/hash/freshness; G4 decryption and archive inspection; G5 single-transaction restore; structured stage evidence; private temp directory and cleanup |
| `scripts/powershell/Test-LabRecovery.ps1` | G6 data and G7 role/ACL/RLS/negative authorization assertions, returning structured results only after all checks |
| `scripts/powershell/Invoke-LabRecoveryReview.ps1` | Actual G1–G8 orchestration; gate results computed from child process outputs and SQL assertions; sanitized evidence output; fails closed |
| `scripts/powershell/Write-LabGateEvidence.ps1` | Explicitly disabled; caller-supplied PASS values prohibited |
| `scripts/powershell/Test-LabSourceProvisionPreflight.ps1` | **New:** read-only source identity, migration role-collision, schema and RLS preflight |
| `scripts/powershell/README-PHASE2.md` | Windows parameters, prerequisites, staged validation plan and known limitations |
| `tests/failure-injection/recovery-failures.Tests.ps1` | Opt-in Pester negative tests for signature, archive tamper, wrong key, wrong target, nonempty target and restore-time failure fixture |
| `docs/PHASE2-FINAL-IMPLEMENTATION-REVIEW.md` | **New:** this review and unresolved risks |

All other Phase 2 files, including SQL migrations, immutable-image-required Compose file, and versioned expectations JSON, are retained. Earlier reports remain historical; this report supersedes execution-readiness statements.

## Eight gates: evidence source and failure behavior

| Gate | Machine-verifiable source | Failure behavior |
| --- | --- | --- |
| G1 backup | marker INSERT acknowledgement and pg_dump producer exit 0 | Stop; remove partial artifacts |
| G2 encryption | age consumer exit 0 and nonempty encrypted artifact | Stop; remove partial artifacts |
| G3 authentication | OpenSSL Ed25519 signature exit 0, archive ID, filename, SHA-256, size and freshness | Reject before decrypt |
| G4 decryption | age exit 0, plaintext nonempty and `pg_restore --list` exit 0 | Stop; remove temporary plaintext |
| G5 restoration | verified Compose project, volume, image, empty target, restricted roles, `pg_restore --single-transaction --exit-on-error` exit 0 | Abort transaction; no success report |
| G6 data | SQL counts, synthetic marker, values, constraints, index, sequences | Fail evidence gate |
| G7 security | SQL role flags/memberships, RLS/FORCE, grants, tenant counts, anonymous/write denials | Fail evidence gate |
| G8 evidence | orchestrator-generated sanitized JSON and monotonic elapsed duration | Missing/failed gate prevents PASS |

**Provenance qualification:** Gate status is derived from the code's own subprocess and assertion outcomes, not caller-supplied PASS values. However, local JSON evidence is not signed or tamper-proof, and its authenticity depends on trust in the runner and filesystem. It is not an external attestation system.

## Prerequisites and proposed staged Windows local validation — NOT EXECUTED

**Stage A (read-only, one command at a time):** Check PowerShell 7 version, installed `age`, `openssl`, `pg_restore`, Docker and Pester; verify independently sourced immutable PostgreSQL 17 digest and target architecture. Inspect protected NTFS ACLs and BitLocker status. Run Compose configuration validation without starting services. Confirm original volumes remain present.

**Stage B (read-only source):** With separate approval to start the synthetic source if needed, run `Test-LabSourceProvisionPreflight.ps1` and inspect role collisions, RLS and grants. No source migration yet.

**Stage C (controlled source migration):** After explicit approval and a verified synthetic source recovery copy, apply the additive Phase 2 source SQL once. Re-run read-only source privilege preflight. Do not change Phase 1 schema files.

**Stage D (disposable target):** Start only the separate Phase 2 Compose project with verified pinned image. Verify container labels and exact new volume. Apply target role provisioning only to the empty disposable database; inspect role flags and memberships.

**Stage E (controlled recovery):** Create restricted artifact, key, evidence and temp directories. Run the eight-gate orchestrator with synthetic data and a deliberately chosen incident timestamp. Review G1–G8 evidence and expected marker. Verify Phase 1 volumes unchanged.

**Stage F (negative tests):** Prepare and approve fixtures independently, run Pester one scenario at a time on fresh disposable targets; never run negative tests against Phase 1 volumes. Require an executable restore-failure fixture whose archive is structurally readable but restore operation fails.

**Stage G:** Produce a sanitized validation report with actual exits, evidence and observed RPO/RTO proxy. Publication remains separately gated.

## Unresolved risk register

| ID | Severity | Finding / action before execution |
| --- | --- | --- |
| R01 | CRITICAL | **Untested code**: PowerShell parser, .NET stream behavior, Docker Compose output, OpenSSL and PostgreSQL compatibility are not verified. Syntax and isolated runtime checks required. |
| R02 | HIGH | Source migration adds `lab_backup`/`lab_marker` LOGIN roles and RLS policies. Preflight exists, but privilege/grant equivalence must be verified against source and restored target. |
| R03 | HIGH | PostgreSQL `pg_dump --enable-row-security` and `pg_restore --no-owner` with policy/ACL restore must be tested. The dump role has broad SELECT on synthetic tables only. |
| R04 | HIGH | Private temporary file is created by age, not atomically opened by orchestrator with a restricted file ACL; directory ACL and BitLocker assumptions must be verified. Host crash can leave plaintext. |
| R05 | HIGH | Current G6/G7 checks validate key invariants but not full schema/ACL semantic equality, sequence next-value correctness or all policy expressions. Extend runtime checks before production-grade claims. |
| R06 | HIGH | Negative tests require approved fixtures and target lifecycle control. Nonempty-target test can only be meaningful in a deliberately populated disposable target. No tests executed. |
| R07 | MEDIUM | Signed manifest freshness + explicit archive ID mitigate accidental replay, but no durable trusted monotonic anti-rollback checkpoint. An authorized older archive can be replayed. |
| R08 | MEDIUM | Immutable digest is mandatory but no digest is supplied; independently verify registry digest, platform and container image ID. |
| R09 | MEDIUM | G1 and G2 use one streaming pipeline; individual exit codes are checked, but independent staged timings are not captured. |
| R10 | MEDIUM | RPO proxy uses marker acknowledgement time, not actual PostgreSQL commit time. Incident timestamp is caller-supplied, and the workflow does not simulate an incident. |
| R11 | MEDIUM | Gate evidence JSON is local and unsigned; protect evidence directory and consider signing reports. |
| R12 | MEDIUM | Windows ACL checker allows Administrators and SYSTEM and checks ACE inheritance, but cannot guarantee BitLocker or exclude privilege escalation. |
| R13 | MEDIUM | Native-process stderr is suppressed to avoid secrets; diagnostic troubleshooting may need a sanitized stderr capture with size limits. |
| R14 | MEDIUM | `pg_restore` timeout and failure handling rely on process tree termination; test process cleanup and target transaction rollback under forced termination. |
| R15 | MEDIUM | Versioned expectations currently cover counts, assets, roles and selected constraints, but need policy-definition and grant-level snapshots for comprehensive parity. |

## Review decision

**Implementation code is present for G1–G8, but remains unvalidated and NOT execution-ready without explicit approval.** This is a static draft, not evidence of a successful disaster recovery run. No production access, GitHub changes, container starts, SQL execution, or volume mutations occurred.
