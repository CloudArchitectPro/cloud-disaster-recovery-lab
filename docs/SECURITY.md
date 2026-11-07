# Security policy and handling

## Data classification

Only fictional data and generic names are allowed. Do not include real project identifiers, server addresses, customer information, database URLs, credentials, backup archives, key material, raw logs, or proprietary schemas.

## Secret management

- Use ignored local environment files or a purpose-built secret manager for future integrations.
- Never commit private age identities, database connection strings, tokens, Terraform state or recovery artifacts.
- `.gitignore` is defense-in-depth, **not** a secret scanner; review the full staged diff and commit history before publication.
- No GitHub Actions secrets are needed for Phase 1 local foundation checks.

## Database and recovery security

- Keep source and recovery on separate volumes; no published DB ports.
- The lab's fixed sample password is **public demo-only** and must never be reused.
- Restore into a verified disposable target, not an arbitrary `DATABASE_URL`.
- Treat SQL dump contents and object names as untrusted until reviewed.
- Apply RLS and grants explicitly; verify with restricted roles, not only owner/superuser.
- For remote connections, require verified TLS and validate certificate failures. Local Docker networking is not TLS.

## CI boundary

GitHub Actions checks run without cloud credentials. `pull_request` does not grant write permissions. Actions should be pinned to immutable SHAs before production-grade supply-chain claims. The initial workflows use major-version tags and therefore do not claim full supply-chain hardening.

## Reporting

Report a vulnerability privately to the maintainer via GitHub's private vulnerability reporting feature if enabled; otherwise open an issue containing **no** exploit secrets or sensitive artifacts. Do not post credentials publicly.

## Publication review

Search all files and Git history for confidential identifiers and secrets; inspect sample data, workflow logs, Mermaid text, metadata and license attribution. Human review remains mandatory.

## Phase 1 hardening note

The source schema now declares read-only NOLOGIN tenant roles and RLS policies (including FORCE RLS); these are **not yet runtime-verified**. The bootstrap owner is a superuser and is not suitable for tenant-isolation tests. The PostgreSQL image uses the `17-bookworm` tag; an immutable digest has not been verified.
