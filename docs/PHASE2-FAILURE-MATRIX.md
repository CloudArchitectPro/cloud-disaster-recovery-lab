# Failure scenarios — proposed acceptance

| Injection | Gate | Expected |
| --- | --- | --- |
| `pg_dump` failure | G1 | No encrypted artifact accepted |
| Invalid age recipient | G2 | No success marker |
| Encrypted artifact changed | G3 | Digest mismatch; no decryption |
| Manifest/signature changed | G3 | Signature rejection |
| Wrong verification public key | G3 | Signature rejection |
| Wrong age identity | G4 | Decryption fails |
| Target project mismatch | G5 | Reject before writes |
| Nonempty target schema | G5 | Reject before writes |
| Missing required target role | G5 | Reject before restore |
| Corrupt decrypted archive | G5 | `pg_restore` fails |
| Missing marker | G6 | Data gate fails |
| Incorrect counts/sequence | G6 | Data gate fails |
| RLS policy absent | G7 | Security gate fails |
| North reads South asset | G7 | Security gate fails |
| Anonymous reads protected data | G7 | Security gate fails |
| Evidence missing gate | G8 | No overall PASS |

Do not inject failures against Phase 1 volumes. All destructive experiments must use separately approved disposable Phase 2 targets. No scenario has been executed.
