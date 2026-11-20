BEGIN;
DROP INDEX IF EXISTS idx_world_sessions_instance_live_character;
DROP INDEX IF EXISTS idx_world_sessions_connected_at_active;
DROP INDEX IF EXISTS idx_characters_created_at;
DROP INDEX IF EXISTS idx_accounts_created_at;
COMMIT;
