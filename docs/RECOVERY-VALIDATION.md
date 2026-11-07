# Recovery validation specification

A recovery is accepted only if **all** applicable checks pass:

- Required schemas, tables, columns, data types and constraints match an explicit manifest.
- Expected per-table counts and deterministic synthetic record digests match.
- Primary keys, foreign keys, unique and check constraints exist and are valid.
- Required indexes exist and are valid.
- Sequences produce nonconflicting values after restore.
- RLS is enabled on protected tables; policies and intended `FORCE ROW LEVEL SECURITY` settings are verified.
- A restricted tenant A cannot read or write tenant B data.
- A restricted anonymous role cannot access protected rows.
- Authenticated-style lab roles receive only intended access. A PostgreSQL role is **not** proof of external authentication recovery.
- Invalid key, corrupted archive and incompatible destination fail without a success report.

Do not test tenant isolation solely as a superuser, table owner or role with `BYPASSRLS`.

**Phase 1:** Specifications only; no recovery validation results exist.

## Phase 1 hardening note

The source schema now declares read-only NOLOGIN tenant roles and RLS policies (including FORCE RLS); these are **not yet runtime-verified**. The bootstrap owner is a superuser and is not suitable for tenant-isolation tests. The PostgreSQL image uses the `17-bookworm` tag; an immutable digest has not been verified.
