BEGIN;

-- Immutable soul-level moral ledger. Deltas are assigned by trusted server rules,
-- never supplied by clients or accepted directly from a world node.
CREATE TABLE soul_fate_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    event_id UUID NOT NULL,
    source VARCHAR(48) NOT NULL,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    karma_delta BIGINT NOT NULL DEFAULT 0,
    merit_delta BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, event_id),
    CHECK (karma_delta <> 0 OR merit_delta <> 0)
);

CREATE INDEX idx_soul_fate_events_soul
    ON soul_fate_events(soul_id, created_at DESC);

COMMIT;
