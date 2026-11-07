# Threat model (design)

## Assets

Encrypted backups, decryption identities, database records, manifests, recovery scripts, recovery environment, CI permissions and sanitized evidence.

## Adversaries and failures

- Unauthorized reader of object storage
- Attacker able to substitute both artifact and checksum
- Compromised CI dependency or action
- Overprivileged database role or broken RLS policy
- Operator targeting the wrong database
- Lost age private identity
- Corrupted or incomplete backup
- Incompatible database extensions or role ownership

## Controls

| Threat | Planned mitigation | Residual risk |
| --- | --- | --- |
| Backup disclosure | Encrypt before storage; least privilege | Stolen decryption identity |
| Tampering | Authenticated manifest; independent restore | Compromised signing/trust root |
| Wrong target | Explicit target allowlist and dry-run checks | Operator/host compromise |
| Cross-tenant read | RLS plus negative role tests | Owner/BYPASSRLS bypass |
| CI exfiltration | Read-only token, no cloud secrets, dependency review | Third-party action compromise |
| Key loss | Separate secured recovery key custody | Unrecoverable archive |
| Backup corruption | Digest check and restore rehearsal | Undetected logical inconsistency |

The controls are **planned**, not evidence of implementation or effectiveness.
