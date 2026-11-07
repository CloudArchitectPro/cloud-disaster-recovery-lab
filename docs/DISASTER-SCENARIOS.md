# Disaster scenarios

All scenarios must run against disposable lab resources only.

| Scenario | Injected failure | Expected validation |
| --- | --- | --- |
| Source loss | Stop/remove source container without deleting backup | Recover to separate target |
| Corrupted encrypted artifact | Change one encrypted byte | Reject before decryption/restore |
| Missing age identity | Withhold private key | Fail closed; no plaintext recovery |
| Wrong target | Supply unapproved database identifier | Refuse before writes |
| Missing role/extension | Restore into incompatible target | Detect and document compatibility failure |
| RLS regression | Deliberately weaken test policy in disposable environment | Negative tenant-access test fails |
| Missing object storage | Make local artifact store unavailable | Bounded failure with no silent success |

No scenario has yet been executed. Do not interpret this table as test results.
