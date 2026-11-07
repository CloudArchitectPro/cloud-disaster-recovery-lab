# Evidence and measurement — proposed

Every phase must record `status`, `started_utc`, `completed_utc`, `elapsed_ms`, `exit_code` (if applicable), and a sanitized reason on failure. Never capture raw dumps, private keys, full environment variables, or authentication material.

Measure observed recovery duration from the synthetic incident declaration until all restore/data/security acceptance gates pass. Also record backup creation and encryption time separately; do not mix backup generation into recovery time unless the incident scenario explicitly includes it.

Measure synthetic marker recovery-point age using the last acknowledged committed marker known present in the restored snapshot and the incident declaration UTC. This is a **conservative proxy**, not the exact age of the latest committed database transaction. Document the no-intervening-writes assumption.

An evidence report is `PASS` only if all required gates pass; missing or unexecuted gates are `NOT_RUN`, not `PASS`. The Phase 1 runtime results were user-reported; Phase 2 has no runtime evidence.
