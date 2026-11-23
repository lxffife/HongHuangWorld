BEGIN;

-- A character may be rescued and defeated again in the same world session.
-- Keep at most one unresolved death per session/character, while retaining
-- the full history of already-resolved deaths.
ALTER TABLE character_death_events
    DROP CONSTRAINT IF EXISTS character_death_events_session_id_character_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_character_death_events_one_pending
    ON character_death_events(session_id, character_id)
    WHERE respawned_at IS NULL;

COMMIT;
