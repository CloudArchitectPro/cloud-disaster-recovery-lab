# Phase 2 implementation draft — NOT EXECUTED

## Invariants

- Preserve all 29 Phase 1 files byte-for-byte.
- Do not touch `cloud-dr-lab_source_data` or `cloud-dr-lab_recovery_data` with restore commands.
- Phase 2 target is `cloud-dr-phase2-validation`, service `restore`, volume `cloud-dr-phase2-validation_phase2_restore_data`.
- The source is the existing `cloud-dr-lab` Compose project and `source` service.
- Only synthetic data and generic identifiers.
- All scripts and commands in this draft require separate execution approval.

## Snapshot and recovery point

1. Apply additive `phase2-source-provision.sql` once, **only after approval**. It adds `lab_dr.recovery_markers`, a restricted backup reader, and a restricted marker writer. It adds read-only backup policies but does not change Phase 1 tenant policies.
2. Insert a unique marker through `lab_marker` in a completed SQL transaction. Wait for the `psql` process to exit successfully; record a UTC acknowledgement time **after** that commit.
3. Run `pg_dump -Fc --schema=lab --schema=lab_dr` as `lab_backup`. PostgreSQL's dump uses a transactionally consistent MVCC snapshot. The completed marker transaction precedes the dump snapshot and must appear in the archive.
4. After restore, check the exact marker ID and recorded timestamp. The acknowledgement time is a conservative **measurement reference**, not the database's exact commit timestamp. The last recoverable transaction across all tables cannot be proven solely by this marker. No writes should occur between marker insertion and dump for the controlled RPO experiment.
5. A marker inserted **after** the dump snapshot must not be expected in the archive. Such a marker may be used as an additional controlled exclusion test in a later phase.

## Privilege model

Source: `lab_backup` LOGIN, SELECT-only on three synthetic tables, their sequences, and `lab_dr.recovery_markers`. RLS policies explicitly permit it to read all synthetic rows. `lab_marker` LOGIN, INSERT/SELECT only on the marker table. Neither is superuser or `BYPASSRLS`; neither is a member of other roles.

The local Docker image uses Unix-socket trust for in-container connections; Docker host administrators can impersonate database roles. This is **not** production authentication. Do not expose container sockets or ports.

Target: tenant roles and `lab_backup` are provisioned `NOLOGIN`, with no memberships. Restore with `lab_owner` inside the isolated container; it is a lab-only superuser. Use `pg_restore --no-owner` while preserving ACLs. The restore process must verify role definitions before proceeding.

## Signed manifest

The manifest is UTF-8 JSON. Sign its **exact bytes** using OpenSSL Ed25519 (`pkeyutl -sign -rawin`); verify the detached signature using an independently trusted public key. It records archive ID, marker ID, marker acknowledgement time, encrypted archive SHA-256 and size, PostgreSQL major version, and scope.

Trust root: the public verification key is supplied via a separately controlled local path, not taken from the untrusted archive directory. Signature alone does not prove the signer was authorized unless that public key is pinned and trusted.

age X25519 public recipient encrypts. Private identity is stored outside repository and artifact storage, protected by Windows ACL/BitLocker. For this first lab, generation and custody of keys are a separately approved manual prerequisite. No keys are bundled.

## Separate acceptance gates

G1 backup: process exit success, nonempty archive stream, committed marker identified.
G2 encryption: age exits zero; encrypted output exists and is nonempty.
G3 manifest: detached Ed25519 signature verified and SHA-256/size match.
G4 decryption: age exits zero into restricted temporary file.
G5 restoration: exact target identity, empty target, role preflight, archive inspection, `pg_restore --single-transaction --exit-on-error --no-owner`.
G6 data: expected tables, counts, marker, constraints, indexes, sequences.
G7 security: role flags/memberships, RLS and FORCE, tenant read isolation, anonymous/write denial.
G8 evidence: sanitized, timestamped JSON report; explicit success only when G1–G7 pass.

A failed gate must prevent all later gates and must not produce a success artifact.

## Important Windows constraints

Do not pipe PostgreSQL binary dumps through a PowerShell text pipeline or `Out-File`. Implement a .NET byte-stream transfer or reviewed temporary-file handling. The proposed scripts use .NET `Process` binary streams. Verify behavior with PowerShell 7 and Docker Desktop before relying on them.

PowerShell's `Stopwatch` is appropriate for durations; UTC clock timestamps are for incident boundaries. Neither replaces a PostgreSQL commit timestamp. Do not call `docker compose down -v` in Phase 2.

## Prerequisites for later execution

PowerShell 7.4+ recommended, Docker Desktop and Compose, PostgreSQL 17 image, age/age-keygen, OpenSSL 3 with Ed25519 support, sufficient local disk, local filesystem key protection, and separately reviewed execution approval.

## Non-goals

No production credentials, remote databases, Cloudflare R2, Terraform, PITR, WAL archival, automated deletion, GitHub changes, or Phase 2 success claims.
