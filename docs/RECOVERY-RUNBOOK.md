# Recovery runbook (design; not yet executable end-to-end)

## Preconditions

- Explicitly identify the **disposable** recovery target and verify it differs from the source.
- Confirm backup origin, expected database major version, age recipient, and trusted integrity manifest.
- Confirm sufficient disk capacity and restricted temporary storage.
- Confirm required PostgreSQL roles, extensions, and object ownership strategy.
- Confirm recovery target is empty or a separately approved replacement.

## Planned procedure

1. Start a clean PostgreSQL 17 recovery instance.
2. Retrieve encrypted archive into a restricted workspace.
3. Verify encrypted-archive digest against a trusted/authenticated manifest.
4. Decrypt using an identity provided outside Git and remove plaintext on exit.
5. Inspect archive with `pg_restore --list`; review object selection and dependencies.
6. Perform a compatible restore using `pg_restore --single-transaction --exit-on-error` and explicit `--no-owner` / `--no-acl` **only when the target role/grant design requires them**. If privileges are omitted, provision intended roles and grants separately.
7. Run validation using non-superuser roles; fail if any assertion fails.
8. Record timing, evidence and remaining service dependencies.
9. Keep the source and recovery instances separate until validation completes.

## Failure handling

Abort on any integrity, decryption, compatibility, restore, or authorization failure. Do not mark recovery successful. Preserve only sanitized diagnostics. A failed single-transaction restore should roll back transactional changes; not every external operation or pre-provisioning step is transactional. Recreate the disposable target before retrying.

**No restore automation has been implemented or tested in Phase 1.**
