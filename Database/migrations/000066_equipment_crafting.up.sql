BEGIN;

CREATE TABLE equipment_crafting_recipes (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    output_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE equipment_crafting_ingredients (
    recipe_id VARCHAR(64) NOT NULL REFERENCES equipment_crafting_recipes(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 999),
    PRIMARY KEY(recipe_id,item_id)
);
CREATE TABLE equipment_crafting_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    request_id UUID NOT NULL,
    recipe_id VARCHAR(64) NOT NULL REFERENCES equipment_crafting_recipes(id),
    output_instance_id UUID NOT NULL REFERENCES item_instances(id) ON DELETE RESTRICT,
    output_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    output_quality SMALLINT NOT NULL CHECK(output_quality BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(character_id,request_id),
    UNIQUE(output_instance_id)
);
CREATE INDEX idx_equipment_crafting_character_time
    ON equipment_crafting_events(character_id,created_at DESC);

INSERT INTO equipment_crafting_recipes(id,name,output_item_id) VALUES
('forge_wolfbone_blade','锻造·荒狼骨刃','wolfbone_short_sword'),
('forge_wolfhide_vest','锻造·荒狼皮甲','wolfhide_vest')
ON CONFLICT(id) DO NOTHING;

INSERT INTO equipment_crafting_ingredients(recipe_id,item_id,quantity) VALUES
('forge_wolfbone_blade','wolf_fang',5),
('forge_wolfbone_blade','wolf_pelt',2),
('forge_wolfhide_vest','wolf_fang',2),
('forge_wolfhide_vest','wolf_pelt',5)
ON CONFLICT(recipe_id,item_id) DO NOTHING;

COMMIT;
