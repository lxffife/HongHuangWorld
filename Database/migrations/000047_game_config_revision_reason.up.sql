BEGIN;
ALTER TABLE game_config_revisions
    ADD COLUMN reason TEXT NOT NULL DEFAULT '';
COMMIT;
