BEGIN;
CREATE INDEX IF NOT EXISTS idx_accounts_created_at ON accounts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_characters_created_at ON characters(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_world_sessions_connected_at_active
 ON world_sessions(connected_at DESC, character_id)
 WHERE connected_at IS NOT NULL AND session_state IN ('active','saving');
CREATE INDEX IF NOT EXISTS idx_world_sessions_instance_live_character
 ON world_sessions(instance_id, character_id)
 WHERE session_state IN ('connecting','active','saving');
COMMIT;
