BEGIN;

-- A soul may complete each authored fusion exactly once. Source mutations stay
-- immutable and are not consumed; the fusion result is a permanent soul asset.
CREATE TABLE soul_fusion_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    recipe_id VARCHAR(48) NOT NULL CHECK (recipe_id IN (
        'battle_body_seal',
        'wind_spirit_seal',
        'undying_seed',
        'five_elements_origin'
    )),
    fusion_name VARCHAR(64) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    strength_bonus SMALLINT NOT NULL DEFAULT 0 CHECK (strength_bonus >= 0),
    constitution_bonus SMALLINT NOT NULL DEFAULT 0 CHECK (constitution_bonus >= 0),
    agility_bonus SMALLINT NOT NULL DEFAULT 0 CHECK (agility_bonus >= 0),
    spirit_bonus SMALLINT NOT NULL DEFAULT 0 CHECK (spirit_bonus >= 0),
    vitality_bonus SMALLINT NOT NULL DEFAULT 0 CHECK (vitality_bonus >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, recipe_id),
    CHECK (
        strength_bonus + constitution_bonus + agility_bonus +
        spirit_bonus + vitality_bonus > 0
    )
);

CREATE INDEX idx_soul_fusion_records_soul
    ON soul_fusion_records(soul_id, created_at DESC);

COMMIT;
