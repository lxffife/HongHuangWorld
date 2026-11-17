BEGIN;

-- One immutable record per transition to a new physical life.
-- Soul identity and soul-level karma/merit remain on the souls row.
CREATE TABLE reincarnation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    previous_character_id UUID NOT NULL REFERENCES characters(id),
    new_character_id UUID NOT NULL UNIQUE REFERENCES characters(id),
    previous_world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    new_world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    previous_race_id VARCHAR(64) NOT NULL REFERENCES race_definitions(id),
    new_race_id VARCHAR(64) NOT NULL REFERENCES race_definitions(id),
    life_index INTEGER NOT NULL CHECK (life_index > 1),
    merit_spent BIGINT NOT NULL DEFAULT 0 CHECK (merit_spent >= 0),
    reincarnated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, life_index),
    UNIQUE (previous_character_id)
);

CREATE INDEX idx_reincarnation_events_soul
    ON reincarnation_events(soul_id, reincarnated_at DESC);

COMMIT;
