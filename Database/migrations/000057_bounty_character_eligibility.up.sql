BEGIN;

ALTER TABLE bounty_tasks
    ADD COLUMN required_character_level INTEGER NOT NULL DEFAULT 1
    CHECK (required_character_level BETWEEN 1 AND 10000);

COMMIT;
