-- Initialization uses the lab_owner superuser; restricted roles cannot seed rows.
INSERT INTO lab.organizations (name) VALUES ('Example North'), ('Example South');
INSERT INTO lab.assets (organization_id, asset_code, status)
VALUES (1, 'SAMPLE-A', 'ready'), (1, 'SAMPLE-B', 'degraded'), (2, 'SAMPLE-C', 'offline');
INSERT INTO lab.recovery_events (asset_id, event_type)
VALUES (1, 'backup'), (1, 'verify'), (3, 'backup');
