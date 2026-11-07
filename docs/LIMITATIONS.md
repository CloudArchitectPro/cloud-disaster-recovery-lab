# Current limitations (publication candidate, November 2026)

- Phase 1 local runtime validation reportedly passed 12 checks; the public repository does not include an independently signed evidence bundle.
- Phase 2 backup/encryption/signature/restore and G1–G8 orchestration code is present, **but has not been executed end-to-end**.
- Phase 2 PowerShell/Pester failure injection, PostgreSQL privilege compatibility, binary streaming, ACL behavior, and process timeout/cleanup require isolated testing.
- The Phase 1 image is a mutable `postgres:17-bookworm` tag. A locally observed digest is not independent registry provenance verification.
- The Phase 2 recovery target is a separate Compose project and volume; a valid Compose merge is not deployment authorization.
- No production data, applications, authentication services, DNS, cross-region replication, PITR, WAL archiving, object-lock, or full SaaS recovery is demonstrated.
- No measured Phase 2 RPO/RTO or application availability is claimed.
- Local Docker network isolation does not establish TLS. Fixed credentials are for a synthetic, isolated demo only.
- Signed manifest checks do not provide a durable trusted anti-rollback checkpoint. Local evidence is not an external attestation.
- Temporary plaintext dump handling and Windows ACL assumptions need explicit validation; a host crash may leave plaintext.
- Read [Phase 2 final implementation review](PHASE2-FINAL-IMPLEMENTATION-REVIEW.md) for the detailed unresolved risk register.
