-- ADDITIVE migration, intended for the synthetic source only.
-- Must be reviewed and run exactly once. Never apply to a production database.
\set ON_ERROR_STOP on
-- Atomic migration: roles and synthetic marker objects are created together.
-- Non-idempotent by design; preflight must reject existing names.
BEGIN;
CREATE ROLE lab_backup LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE lab_marker LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE SCHEMA lab_dr;
CREATE TABLE lab_dr.recovery_markers (
  marker_id uuid PRIMARY KEY,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON SCHEMA lab_dr FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA lab_dr FROM PUBLIC;
GRANT CONNECT ON DATABASE labdb TO lab_backup, lab_marker;
GRANT USAGE ON SCHEMA lab TO lab_backup;
GRANT USAGE ON SCHEMA lab_dr TO lab_backup, lab_marker;
GRANT SELECT ON ALL TABLES IN SCHEMA lab TO lab_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA lab TO lab_backup;
GRANT SELECT ON lab_dr.recovery_markers TO lab_backup, lab_marker;
GRANT INSERT ON lab_dr.recovery_markers TO lab_marker;
ALTER TABLE lab_dr.recovery_markers ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_dr.recovery_markers FORCE ROW LEVEL SECURITY;
CREATE POLICY marker_backup_read ON lab_dr.recovery_markers FOR SELECT TO lab_backup USING (true);
CREATE POLICY marker_writer_read ON lab_dr.recovery_markers FOR SELECT TO lab_marker USING (true);
CREATE POLICY marker_writer_insert ON lab_dr.recovery_markers FOR INSERT TO lab_marker WITH CHECK (true);
-- Backup reader sees every synthetic tenant without global BYPASSRLS privilege.
CREATE POLICY org_backup_read ON lab.organizations FOR SELECT TO lab_backup USING (true);
CREATE POLICY asset_backup_read ON lab.assets FOR SELECT TO lab_backup USING (true);
CREATE POLICY event_backup_read ON lab.recovery_events FOR SELECT TO lab_backup USING (true);
COMMIT;
-- Existing Phase 1 tenant policies are not altered.
