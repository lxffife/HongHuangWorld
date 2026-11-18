BEGIN;
DROP TABLE IF EXISTS game_projection_versions;
DROP INDEX IF EXISTS idx_game_projection_inbox_processed;
COMMIT;
