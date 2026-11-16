BEGIN;

-- Static cultivation realm catalogue. Progression is data-driven so balance can
-- be tuned without changing application code.
CREATE TABLE realm_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(48) NOT NULL,
    realm_order SMALLINT NOT NULL UNIQUE CHECK (realm_order > 0),
    max_stage SMALLINT NOT NULL DEFAULT 9 CHECK (max_stage > 0),
    required_cultivation BIGINT NOT NULL DEFAULT 0 CHECK (required_cultivation >= 0)
);

INSERT INTO realm_definitions (id, name, realm_order, max_stage, required_cultivation)
VALUES
    ('qi_refining', '炼气期', 1, 9, 0),
    ('foundation_establishment', '筑基期', 2, 9, 10000),
    ('golden_core', '金丹期', 3, 9, 100000),
    ('nascent_soul', '元婴期', 4, 9, 1000000),
    ('spirit_transformation', '化神期', 5, 9, 10000000),
    ('void_refinement', '炼虚期', 6, 9, 100000000),
    ('body_integration', '合体期', 7, 9, 1000000000),
    ('mahayana', '大乘期', 8, 9, 10000000000),
    ('tribulation_transcendence', '渡劫期', 9, 9, 100000000000)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE character_attributes (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    strength INTEGER NOT NULL DEFAULT 5 CHECK (strength >= 0),
    constitution INTEGER NOT NULL DEFAULT 5 CHECK (constitution >= 0),
    agility INTEGER NOT NULL DEFAULT 5 CHECK (agility >= 0),
    spirit INTEGER NOT NULL DEFAULT 5 CHECK (spirit >= 0),
    vitality INTEGER NOT NULL DEFAULT 5 CHECK (vitality >= 0),
    health INTEGER NOT NULL DEFAULT 100 CHECK (health >= 0),
    max_health INTEGER NOT NULL DEFAULT 100 CHECK (max_health > 0),
    mana INTEGER NOT NULL DEFAULT 50 CHECK (mana >= 0),
    max_mana INTEGER NOT NULL DEFAULT 50 CHECK (max_mana >= 0),
    attack INTEGER NOT NULL DEFAULT 10 CHECK (attack >= 0),
    defense INTEGER NOT NULL DEFAULT 5 CHECK (defense >= 0),
    movement_speed REAL NOT NULL DEFAULT 5.0 CHECK (movement_speed > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (health <= max_health),
    CHECK (mana <= max_mana)
);

CREATE TABLE character_progression (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    experience BIGINT NOT NULL DEFAULT 0 CHECK (experience >= 0),
    cultivation BIGINT NOT NULL DEFAULT 0 CHECK (cultivation >= 0),
    realm_id VARCHAR(64) NOT NULL DEFAULT 'qi_refining' REFERENCES realm_definitions(id),
    realm_stage SMALLINT NOT NULL DEFAULT 1 CHECK (realm_stage > 0),
    unspent_attribute_points INTEGER NOT NULL DEFAULT 0 CHECK (unspent_attribute_points >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Backfill any characters created before this migration.
INSERT INTO character_attributes (character_id)
SELECT id FROM characters
ON CONFLICT (character_id) DO NOTHING;

INSERT INTO character_progression (character_id)
SELECT id FROM characters
ON CONFLICT (character_id) DO NOTHING;

COMMIT;
