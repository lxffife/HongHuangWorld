BEGIN;

-- Every reincarnated body receives one immutable, server-derived fate trait.
-- Gameplay systems (NPC disposition, hidden encounters and route gates) can
-- query this record without recalculating the soul's later-changing ledger.
CREATE TABLE character_fate_traits (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    life_index INTEGER NOT NULL CHECK (life_index > 1),
    trait_id VARCHAR(48) NOT NULL CHECK (
        trait_id IN ('unmarked_fate', 'blessed_fate', 'karmic_shadow', 'entangled_fate')
    ),
    trait_name VARCHAR(32) NOT NULL,
    description TEXT NOT NULL,
    effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, life_index)
);

CREATE INDEX idx_character_fate_traits_soul
    ON character_fate_traits(soul_id, life_index DESC);

COMMIT;
