# Architecture

**Status:** Proposed target design. Only static foundation files are prepared.

## Trust boundaries

1. **Source:** PostgreSQL 17 container with synthetic tenant data, its own named volume.
2. **Backup workspace:** planned ephemeral process with minimum database read privileges; decrypted artifacts are transient.
3. **Artifact store:** local, non-cloud storage in the first executable recovery phase. S3-compatible services are optional later.
4. **Recovery:** separate PostgreSQL 17 container and volume; never the source database.
5. **Evidence:** sanitized counts, statuses and timings; no raw dumps or unreviewed logs in Git.

The Compose foundation places both databases on an internal Docker network without published ports. This prevents direct host port access, **not** all access by host administrators or other privileged Docker users.

## Recovery contract

The recovery target is disposable and explicitly named. A backup manifest identifies archive format, expected database major version, digest, creation time and recovery scope. Restore scripts must refuse an unexpected target, missing key, failed digest, incompatible version, or non-empty target unless a deliberate override is approved.

`pg_restore --single-transaction --exit-on-error` is intended for a compatible custom-format archive; incompatible global objects, extensions, privileges and ownership must be handled explicitly. Database globals and external identity services are not covered by application-schema backup.

## Transport security

The local lab uses an internal Docker network; it does **not** claim TLS. A later remote integration must use verified TLS (`sslmode=verify-full` with trusted CA and correct hostname) and test rejection of invalid certificates.

## Cloud extension

Optional R2/S3 integration must be opt-in, use scoped credentials, prohibit public buckets, encrypt before upload, and avoid recording object keys or endpoint identifiers in published evidence.

## Phase 1 hardening note

The source schema now declares read-only NOLOGIN tenant roles and RLS policies (including FORCE RLS); these are **not yet runtime-verified**. The bootstrap owner is a superuser and is not suitable for tenant-isolation tests. The PostgreSQL image uses the `17-bookworm` tag; an immutable digest has not been verified.
