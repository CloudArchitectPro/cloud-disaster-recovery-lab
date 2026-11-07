# RPO / RTO methodology

**RPO (objective):** maximum acceptable data loss measured as time. For scheduled logical backups, worst-case exposure can approach the backup interval plus any delay in creating or validating a usable backup.

**Observed recovery point:** timestamp of the latest committed synthetic change known to be present in the restored dataset. Record the incident reference time and compute the age of the restored recovery point; do not confuse this with the declared RPO target.

**RTO (objective):** maximum acceptable time from incident declaration to the explicitly defined service recovery criterion.

**Observed recovery duration:** end-to-end elapsed time from declared incident to passing the defined acceptance checks. Report backup retrieval, decrypt, restore and validation subtimings, but do not substitute restore command duration for service RTO.

## Evidence template

| Field | Value |
| --- | --- |
| Scenario | Not run |
| Declared incident time | Not measured |
| Latest recoverable change | Not measured |
| Acceptance-check completion | Not measured |
| Observed recovery point age | Not measured |
| Observed recovery duration | Not measured |
| Declared RPO target | Not set |
| Declared RTO target | Not set |

No targets or results have been fabricated.
