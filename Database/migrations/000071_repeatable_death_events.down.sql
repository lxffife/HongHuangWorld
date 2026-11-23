BEGIN;

DROP INDEX IF EXISTS idx_character_death_events_one_pending;

ALTER TABLE character_death_events
    ADD CONSTRAINT character_death_events_session_id_character_id_key
    UNIQUE (session_id, character_id);

COMMIT;
