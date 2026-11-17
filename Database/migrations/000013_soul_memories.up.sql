BEGIN;

-- Memories are stored against the persistent soul, not the replaceable body.
-- Their content is withheld until the soul reaches the configured realm order.
CREATE TABLE soul_memory_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    source_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE RESTRICT,
    memory_type VARCHAR(32) NOT NULL,
    title VARCHAR(128) NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    memory_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    min_realm_order SMALLINT NOT NULL DEFAULT 5 CHECK (min_realm_order > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, source_character_id, memory_type)
);

CREATE INDEX idx_soul_memory_entries_soul
    ON soul_memory_entries(soul_id, created_at DESC);

COMMIT;
