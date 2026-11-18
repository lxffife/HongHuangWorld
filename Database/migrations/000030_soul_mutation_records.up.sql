BEGIN;

-- Mutation outcomes are attached to one trusted absorption event and are
-- immutable soul-owned history. Event uniqueness prevents reroll exploits.
CREATE TABLE soul_mutation_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    event_id UUID NOT NULL,
    mutation_key VARCHAR(64) NOT NULL,
    mutation_name VARCHAR(48) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    rarity VARCHAR(16) NOT NULL CHECK (rarity IN ('uncommon','rare')),
    attribute VARCHAR(24) NOT NULL CHECK (attribute IN
        ('strength','constitution','agility','spirit','vitality')),
    attribute_bonus SMALLINT NOT NULL CHECK (attribute_bonus BETWEEN 1 AND 2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id,event_id)
);

CREATE INDEX idx_soul_mutation_records_soul
    ON soul_mutation_records(soul_id,created_at DESC);

COMMIT;
