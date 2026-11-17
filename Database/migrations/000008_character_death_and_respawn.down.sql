BEGIN;

DROP INDEX IF EXISTS idx_character_death_events_pending;
DROP TABLE IF EXISTS character_death_events;

COMMIT;
