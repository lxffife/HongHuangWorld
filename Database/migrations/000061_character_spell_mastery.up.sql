BEGIN;

CREATE TABLE character_spell_mastery (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    spell_id VARCHAR(64) NOT NULL CHECK (spell_id IN ('fireball','ice_bolt')),
    experience BIGINT NOT NULL DEFAULT 0 CHECK (experience BETWEEN 0 AND 4500),
    level SMALLINT NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 10),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, spell_id)
);

CREATE TABLE character_spell_mastery_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    server_id UUID NOT NULL REFERENCES server_registry(id),
    event_id UUID NOT NULL,
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    spell_id VARCHAR(64) NOT NULL CHECK (spell_id IN ('fireball','ice_bolt')),
    experience_awarded SMALLINT NOT NULL CHECK (experience_awarded BETWEEN 1 AND 10),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (server_id, event_id)
);

CREATE INDEX idx_character_spell_mastery_events_character
    ON character_spell_mastery_events(character_id, created_at DESC);

COMMIT;
