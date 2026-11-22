BEGIN;

-- Equipment drops become unique item instances. Materials and consumables keep
-- using the existing stack-based character_inventory table.
CREATE TABLE equipment_affix_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    equipment_slot VARCHAR(24) NOT NULL CHECK (equipment_slot IN ('any','weapon','head','chest','legs','boots','accessory')),
    stat_key VARCHAR(32) NOT NULL CHECK (stat_key IN ('attack','defense','strength','constitution','agility','spirit','vitality','max_health','max_mana','movement_speed')),
    min_value INTEGER NOT NULL,
    max_value INTEGER NOT NULL CHECK (max_value >= min_value),
    weight INTEGER NOT NULL DEFAULT 100 CHECK (weight > 0),
    min_quality SMALLINT NOT NULL DEFAULT 1 CHECK (min_quality BETWEEN 1 AND 5),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX idx_equipment_affix_roll ON equipment_affix_definitions(equipment_slot, min_quality) WHERE enabled;

CREATE TABLE item_instances (
    id UUID PRIMARY KEY,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quality SMALLINT NOT NULL CHECK (quality BETWEEN 1 AND 5),
    rolled_stats JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(rolled_stats) = 'object'),
    affixes JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(affixes) = 'array'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE ground_drops
    ADD COLUMN item_instance_id UUID UNIQUE REFERENCES item_instances(id) ON DELETE RESTRICT;
CREATE TABLE character_item_instances (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    item_instance_id UUID NOT NULL UNIQUE REFERENCES item_instances(id) ON DELETE RESTRICT,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, item_instance_id)
);
ALTER TABLE character_equipment
    ADD COLUMN item_instance_id UUID UNIQUE REFERENCES item_instances(id) ON DELETE RESTRICT;

-- Early-game wolves can now drop real, independently rolled equipment.
INSERT INTO item_definitions (id,name,category,quality,max_stack,icon_key,description,equipment_slot,base_stats) VALUES
('wolfbone_short_sword','荒狼骨刃','equipment',2,1,'weapon_wolfbone_blade','以荒狼骨骼打磨而成的短刃，轻巧而锋利。','weapon','{"attack":8,"strength":1}'::jsonb),
('wolfhide_vest','荒狼皮甲','equipment',2,1,'armor_wolfhide_vest','以荒狼皮革鞣制的护胸，兼具韧性与灵活性。','chest','{"defense":4,"vitality":1}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO monster_loot_entries (monster_id,item_id,drop_chance_bp,min_quantity,max_quantity) VALUES
('wilderness_wolf','wolfbone_short_sword',450,1,1),
('wilderness_wolf','wolfhide_vest',350,1,1)
ON CONFLICT (monster_id,item_id) DO NOTHING;

INSERT INTO equipment_affix_definitions (id,name,equipment_slot,stat_key,min_value,max_value,weight,min_quality) VALUES
('weapon_attack_keen','锋锐','weapon','attack',2,5,100,1),
('weapon_strength','强力','weapon','strength',1,3,80,1),
('weapon_agility','迅捷','weapon','agility',1,3,80,2),
('armor_defense_firm','坚固','any','defense',1,4,100,1),
('armor_constitution','厚土','any','constitution',1,3,80,1),
('armor_vitality','生机','any','vitality',1,3,80,2),
('armor_health','护体','any','max_health',5,20,60,2),
('accessory_spirit','灵蕴','accessory','spirit',1,4,100,1),
('accessory_mana','聚灵','accessory','max_mana',5,20,80,2),
('accessory_movement','踏风','accessory','movement_speed',1,2,50,3)
ON CONFLICT (id) DO NOTHING;

COMMIT;
