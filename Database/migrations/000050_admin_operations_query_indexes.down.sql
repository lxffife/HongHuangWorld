BEGIN;

DROP INDEX IF EXISTS idx_world_sessions_active_connected_at;
DROP INDEX IF EXISTS idx_admin_audit_logs_action_result_created;

COMMIT;
