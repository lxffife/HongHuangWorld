BEGIN;

CREATE TABLE equipment_salvage_recipes (
    equipment_item_id VARCHAR(64) PRIMARY KEY REFERENCES item_definitions(id) ON DELETE CASCADE,
    material_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    base_quantity INTEGER NOT NULL CHECK (base_quantity BETWEEN 1 AND 99),
    per_quality_bonus INTEGER NOT NULL DEFAULT 0 CHECK (per_quality_bonus BETWEEN 0 AND 20),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE equipment_salvage_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    request_id UUID NOT NULL,
    item_instance_id UUID NOT NULL,
    equipment_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    material_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    material_quantity INTEGER NOT NULL CHECK (material_quantity > 0),
    equipment_quality SMALLINT NOT NULL CHECK (equipment_quality BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (character_id, request_id),
    UNIQUE (character_id, item_instance_id)
);
CREATE INDEX idx_equipment_salvage_character_time
    ON equipment_salvage_events(character_id, created_at DESC);

-- Salvage turns duplicate early-game wolf equipment into useful crafting materials.
INSERT INTO equipment_salvage_recipes
(equipment_item_id, material_item_id, base_quantity, per_quality_bonus)
VALUES
('wolfbone_short_sword', 'wolf_fang', 2, 1),
('wolfhide_vest', 'wolf_pelt', 2, 1)
ON CONFLICT (equipment_item_id) DO NOTHING;

COMMIT;
