BEGIN;

-- Soul essence belongs to the persistent soul, never to an individual body.
CREATE TABLE soul_essence_attributes (
    soul_id UUID PRIMARY KEY REFERENCES souls(id) ON DELETE CASCADE,
    soul_power BIGINT NOT NULL DEFAULT 0 CHECK (soul_power >= 0),
    soul_wisdom BIGINT NOT NULL DEFAULT 0 CHECK (soul_wisdom >= 0),
    soul_resilience BIGINT NOT NULL DEFAULT 0 CHECK (soul_resilience >= 0),
    soul_perception BIGINT NOT NULL DEFAULT 0 CHECK (soul_perception >= 0),
    absorption_capacity BIGINT NOT NULL DEFAULT 100 CHECK (absorption_capacity >= 0),
    absorbed_energy BIGINT NOT NULL DEFAULT 0 CHECK (absorbed_energy >= 0),
    absorbed_count BIGINT NOT NULL DEFAULT 0 CHECK (absorbed_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (absorbed_energy <= absorption_capacity)
);

INSERT INTO soul_essence_attributes (soul_id)
SELECT id FROM souls
ON CONFLICT (soul_id) DO NOTHING;

-- The catalogue describes authored soul-creature categories. It does not grant
-- player rewards; trusted absorption rules will be added with the combat flow.
CREATE TABLE soul_absorption_kinds (
    id VARCHAR(48) PRIMARY KEY,
    name VARCHAR(48) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    base_energy BIGINT NOT NULL CHECK (base_energy > 0),
    trait_key VARCHAR(48) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO soul_absorption_kinds (id,name,description,base_energy,trait_key) VALUES
('ordinary_wraith','普通游魂','提供基础魂力，适合初生魂光吸收',5,'wraith_affinity'),
('beast_spirit','兽魂','蕴含野性与体魄记忆，影响未来肉身根骨倾向',12,'beast_affinity'),
('battle_spirit','战魂','残留战斗本能与技艺记忆，影响战斗天赋倾向',15,'martial_affinity')
ON CONFLICT (id) DO NOTHING;

-- Immutable audit ledger. event_id is supplied by the trusted world server
-- in the future and deduplicated per soul to prevent repeated absorption.
CREATE TABLE soul_absorption_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    event_id UUID NOT NULL,
    source_entity_id VARCHAR(96) NOT NULL,
    absorption_kind_id VARCHAR(48) NOT NULL REFERENCES soul_absorption_kinds(id),
    energy_gained BIGINT NOT NULL CHECK (energy_gained > 0),
    trait_key VARCHAR(48) NOT NULL,
    trait_value BIGINT NOT NULL DEFAULT 1 CHECK (trait_value > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id,event_id)
);

CREATE INDEX idx_soul_absorption_records_soul
    ON soul_absorption_records(soul_id,created_at DESC);

COMMIT;
