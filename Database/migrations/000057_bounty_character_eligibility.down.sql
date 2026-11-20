BEGIN;

ALTER TABLE bounty_tasks
    DROP COLUMN IF EXISTS required_character_level;

COMMIT;
