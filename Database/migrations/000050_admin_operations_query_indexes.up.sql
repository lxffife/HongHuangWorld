BEGIN;

-- Admin audit filtering commonly combines action/result with a time range.
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_action_result_created
    ON admin_audit_logs(action, result, created_at DESC, id DESC);

-- The live-session console reads only active sessions and orders by connection time.
CREATE INDEX IF NOT EXISTS idx_world_sessions_active_connected_at
    ON world_sessions(connected_at DESC, id DESC)
    WHERE session_state = 'active';

COMMIT;
