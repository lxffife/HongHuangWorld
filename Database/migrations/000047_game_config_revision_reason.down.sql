BEGIN;
ALTER TABLE game_config_revisions
    DROP COLUMN IF EXISTS reason;
COMMIT;
