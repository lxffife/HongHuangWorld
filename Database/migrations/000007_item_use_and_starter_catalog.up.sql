BEGIN;

CREATE TABLE item_use_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    request_id UUID NOT NULL,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    effect_applied JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (character_id, request_id)
);
CREATE INDEX idx_item_use_events_character ON item_use_events(character_id, created_at DESC);

INSERT INTO item_definitions (id,name,category,quality,max_stack,icon_key,description,equipment_slot,base_stats) VALUES
('starter_iron_sword','粗铁剑','equipment',1,1,'weapon_iron_sword','一把适合初入修行之人的铁剑。','weapon','{"attack":5}'),
('starter_cloth_cap','布制头巾','equipment',1,1,'armor_cloth_cap','简单的布制头巾。','head','{"defense":1}'),
('starter_leather_vest','粗皮护胸','equipment',1,1,'armor_leather_vest','以荒兽皮革缝制的基础护胸。','chest','{"defense":3,"max_health":10}'),
('starter_trousers','修行长裤','equipment',1,1,'armor_trousers','便于行动的基础长裤。','legs','{"defense":1}'),
('starter_travel_boots','行旅布靴','equipment',1,1,'armor_travel_boots','适合长途跋涉的布靴。','boots','{"agility":1}'),
('starter_wooden_charm','护身木符','equipment',1,1,'accessory_wooden_charm','刻有简易护身纹路的木符。','accessory','{"defense":1,"max_mana":5}')
ON CONFLICT (id) DO NOTHING;

INSERT INTO item_definitions (id,name,category,quality,max_stack,icon_key,description,use_effect) VALUES
('minor_health_pill','小还元丹','consumable',1,99,'consumable_health_pill','服用后恢复少量生命。','{"heal_health":30}'),
('minor_mana_pill','小聚灵丹','consumable',1,99,'consumable_mana_pill','服用后恢复少量灵力。','{"restore_mana":20}')
ON CONFLICT (id) DO NOTHING;

COMMIT;
