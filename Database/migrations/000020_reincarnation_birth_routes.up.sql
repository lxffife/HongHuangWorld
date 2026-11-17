BEGIN;

-- initial_boon is reserved descriptive configuration in this slice; the
-- current implementation does not grant route-specific inventory/resources.
CREATE TABLE reincarnation_birth_routes (
    id VARCHAR(96) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    race_id VARCHAR(64) REFERENCES race_definitions(id),
    fate_trait_id VARCHAR(32) CHECK (
        fate_trait_id IS NULL OR fate_trait_id IN
        ('unmarked_fate', 'blessed_fate', 'karmic_shadow', 'entangled_fate')
    ),
    name VARCHAR(80) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    spawn_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    spawn_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    spawn_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    initial_boon JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_order INTEGER NOT NULL DEFAULT 100,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (length(id) BETWEEN 1 AND 96),
    CHECK (spawn_x BETWEEN -10000 AND 10000),
    CHECK (spawn_y BETWEEN -1000 AND 1000),
    CHECK (spawn_z BETWEEN -10000 AND 10000)
);

ALTER TABLE reincarnation_events
    ADD COLUMN birth_route_id VARCHAR(96),
    ADD COLUMN birth_route_name VARCHAR(80) NOT NULL DEFAULT '',
    ADD COLUMN birth_route_description TEXT NOT NULL DEFAULT '',
    ADD COLUMN birth_route_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX idx_reincarnation_birth_routes_world
    ON reincarnation_birth_routes(world_id, enabled, sort_order);

-- The first playable world server is Qingyun. Human and demon routes share
-- that deployed world instance but have distinct, server-owned spawn points.
INSERT INTO reincarnation_birth_routes
    (id, world_id, race_id, name, description, spawn_x, spawn_y, spawn_z, initial_boon, sort_order)
VALUES
    ('qingyun_human_misty_valley', 'qingyun_human', 'human',
     '青云·灵溪谷', '青云山脉灵溪上游，灵气平和，适合人族初入仙途。',
     12.0, 0.0, -8.0, '{"kind":"starter_region","affinity":"spirit"}'::jsonb, 10),
    ('qingyun_demon_beast_ridge', 'qingyun_human', 'demon',
     '青云·百兽岭', '青云山脉外围的古林山岭，妖气与灵气交汇，适合妖族显化本相。',
     -18.0, 0.0, 14.0, '{"kind":"starter_region","affinity":"beast"}'::jsonb, 20)
ON CONFLICT (id) DO NOTHING;

COMMIT;
