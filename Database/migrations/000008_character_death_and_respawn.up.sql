BEGIN;

CREATE TABLE character_death_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES world_sessions(id),
    world_id VARCHAR(96) NOT NULL REFERENCES world_definitions(id),
    death_reason VARCHAR(48) NOT NULL DEFAULT 'combat',
    died_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    respawned_at TIMESTAMPTZ,
    respawn_world_id VARCHAR(96) REFERENCES world_definitions(id),
    UNIQUE (session_id, character_id)
);
CREATE INDEX idx_character_death_events_pending
    ON character_death_events(character_id, died_at DESC)
    WHERE respawned_at IS NULL;

COMMIT;
