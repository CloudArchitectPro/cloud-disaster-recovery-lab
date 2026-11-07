# Backup strategy

**Planned:** `pg_dump --format=custom` from a transactionally consistent PostgreSQL snapshot. This is a logical backup, not continuous WAL archiving or PITR.

1. Validate source is the designated lab instance.
2. Create a custom-format archive with PostgreSQL 17 tooling.
3. Encrypt archive using an age recipient public key; do not put the private identity in the repository.
4. Calculate SHA-256 over the encrypted artifact. Protect the digest/manifest with a trusted authenticated channel or signature so an attacker cannot replace both.
5. Write encrypted artifact to a local restricted directory. Remote S3-compatible storage is a later opt-in.
6. Verify decryptability and perform an independent restore rehearsal; a successful upload alone is insufficient.

**Retention:** A proposed policy, not implemented: daily copies for 7 days and weekly copies for 4 weeks, subject to storage and recovery requirements. Deletion and key retention must be coordinated.

**Failure behavior:** Nonzero exit, no success marker, no raw sensitive output, and cleanup of temporary plaintext. Never delete the only recoverable copy during rotation.

**Limitations:** `pg_dump` does not include all cluster globals, identity-provider state, or WAL for point-in-time recovery. Restore tests determine actual usability.
