BEGIN;

CREATE TABLE item_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    category VARCHAR(24) NOT NULL CHECK (category IN ('material', 'consumable', 'equipment', 'quest')),
    quality SMALLINT NOT NULL DEFAULT 1 CHECK (quality BETWEEN 1 AND 5),
    max_stack INTEGER NOT NULL DEFAULT 99 CHECK (max_stack BETWEEN 1 AND 9999),
    icon_key VARCHAR(96) NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE monster_loot_entries (
    monster_id VARCHAR(64) NOT NULL,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    drop_chance_bp INTEGER NOT NULL CHECK (drop_chance_bp BETWEEN 0 AND 10000),
    min_quantity INTEGER NOT NULL CHECK (min_quantity > 0),
    max_quantity INTEGER NOT NULL CHECK (max_quantity >= min_quantity),
    PRIMARY KEY (monster_id, item_id)
);

CREATE TABLE ground_drops (
    id UUID PRIMARY KEY,
    server_id UUID NOT NULL REFERENCES server_registry(id),
    session_id UUID NOT NULL REFERENCES world_sessions(id),
    owner_character_id UUID NOT NULL REFERENCES characters(id),
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    position_x DOUBLE PRECISION NOT NULL,
    position_z DOUBLE PRECISION NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'picked', 'expired')),
    expires_at TIMESTAMPTZ NOT NULL,
    picked_by_character_id UUID REFERENCES characters(id),
    picked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (server_id, id)
);
CREATE INDEX idx_ground_drops_world_available ON ground_drops(server_id, status, expires_at);
CREATE INDEX idx_ground_drops_owner ON ground_drops(owner_character_id, status, expires_at);

CREATE TABLE character_inventory (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, item_id)
);

CREATE TABLE item_pickup_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id UUID NOT NULL REFERENCES server_registry(id),
    event_id UUID NOT NULL,
    drop_id UUID NOT NULL,
    character_id UUID NOT NULL REFERENCES characters(id),
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (server_id, event_id),
    UNIQUE (server_id, drop_id)
);
CREATE INDEX idx_item_pickup_events_character ON item_pickup_events(character_id, created_at DESC);

INSERT INTO item_definitions (id, name, category, quality, max_stack, icon_key, description) VALUES
    ('wolf_fang', '荒狼獠牙', 'material', 1, 99, 'material_wolf_fang', '荒原狼脱落的獠牙，可用于基础锻造'),
    ('wolf_pelt', '荒狼皮', 'material', 1, 99, 'material_wolf_pelt', '质地粗糙的兽皮，可用于制作初级护具')
ON CONFLICT (id) DO NOTHING;

INSERT INTO monster_loot_entries (monster_id, item_id, drop_chance_bp, min_quantity, max_quantity) VALUES
    ('wilderness_wolf', 'wolf_fang', 6500, 1, 2),
    ('wilderness_wolf', 'wolf_pelt', 3000, 1, 1)
ON CONFLICT (monster_id, item_id) DO NOTHING;

COMMIT;
