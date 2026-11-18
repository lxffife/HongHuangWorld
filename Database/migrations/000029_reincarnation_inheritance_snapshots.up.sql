BEGIN;

-- Immutable snapshot of soul inheritance applied to each newly reincarnated body.
-- Potential belongs to the soul; applied bonuses belong to this physical life.
CREATE TABLE character_birth_inheritance (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    life_index INTEGER NOT NULL CHECK (life_index > 1),
    source_absorbed_count BIGINT NOT NULL DEFAULT 0 CHECK (source_absorbed_count >= 0),
    source_growth_stage SMALLINT NOT NULL CHECK (source_growth_stage BETWEEN 1 AND 5),
    source_growth_name VARCHAR(32) NOT NULL,
    source_strength BIGINT NOT NULL DEFAULT 0 CHECK (source_strength >= 0),
    source_constitution BIGINT NOT NULL DEFAULT 0 CHECK (source_constitution >= 0),
    source_agility BIGINT NOT NULL DEFAULT 0 CHECK (source_agility >= 0),
    source_spirit BIGINT NOT NULL DEFAULT 0 CHECK (source_spirit >= 0),
    source_vitality BIGINT NOT NULL DEFAULT 0 CHECK (source_vitality >= 0),
    race_strength_weight INTEGER NOT NULL CHECK (race_strength_weight >= 0),
    race_constitution_weight INTEGER NOT NULL CHECK (race_constitution_weight >= 0),
    race_agility_weight INTEGER NOT NULL CHECK (race_agility_weight >= 0),
    race_spirit_weight INTEGER NOT NULL CHECK (race_spirit_weight >= 0),
    race_vitality_weight INTEGER NOT NULL CHECK (race_vitality_weight >= 0),
    applied_strength SMALLINT NOT NULL DEFAULT 0 CHECK (applied_strength BETWEEN 0 AND 3),
    applied_constitution SMALLINT NOT NULL DEFAULT 0 CHECK (applied_constitution BETWEEN 0 AND 3),
    applied_agility SMALLINT NOT NULL DEFAULT 0 CHECK (applied_agility BETWEEN 0 AND 3),
    applied_spirit SMALLINT NOT NULL DEFAULT 0 CHECK (applied_spirit BETWEEN 0 AND 3),
    applied_vitality SMALLINT NOT NULL DEFAULT 0 CHECK (applied_vitality BETWEEN 0 AND 3),
    dominant_attribute VARCHAR(24) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, life_index),
    CHECK (dominant_attribute IN ('','strength','constitution','agility','spirit','vitality'))
);

CREATE INDEX idx_character_birth_inheritance_soul
    ON character_birth_inheritance(soul_id, life_index DESC);

COMMIT;
