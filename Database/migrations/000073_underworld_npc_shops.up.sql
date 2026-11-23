BEGIN;

CREATE TABLE npc_shop_definitions (
    id VARCHAR(64) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    display_name VARCHAR(96) NOT NULL,
    shop_type VARCHAR(32) NOT NULL CHECK (shop_type IN ('weapon', 'alchemy', 'talisman', 'formation', 'artifact', 'general')),
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    description TEXT NOT NULL DEFAULT '',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_npc_shop_world_enabled ON npc_shop_definitions(world_id, enabled, shop_type);

CREATE TABLE npc_shop_items (
    shop_id VARCHAR(64) NOT NULL REFERENCES npc_shop_definitions(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    unit_price BIGINT NOT NULL CHECK (unit_price > 0),
    stock_quantity BIGINT CHECK (stock_quantity IS NULL OR stock_quantity >= 0),
    sort_order INTEGER NOT NULL DEFAULT 0,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (shop_id, item_id)
);

CREATE TABLE npc_shop_purchase_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL,
    character_id UUID NOT NULL REFERENCES characters(id),
    request_id UUID NOT NULL,
    shop_id VARCHAR(64) NOT NULL REFERENCES npc_shop_definitions(id),
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    total_price BIGINT NOT NULL CHECK (total_price > 0),
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, request_id)
);
CREATE INDEX idx_npc_shop_purchase_character_time
    ON npc_shop_purchase_events(character_id, created_at DESC);

INSERT INTO npc_shop_definitions
(id, world_id, display_name, shop_type, currency_id, description)
VALUES
('fengdu_weapon_shop', 'underworld_fengdu', '酆都百兵铺', 'weapon', 'ghost_cash', '售卖初阶兵器与基础防具'),
('fengdu_elixir_shop', 'underworld_fengdu', '黄泉丹药坊', 'alchemy', 'ghost_cash', '售卖疗伤与恢复类基础丹药'),
('fengdu_talisman_shop', 'underworld_fengdu', '镇魂符箓铺', 'talisman', 'ghost_cash', '售卖护身与镇邪类基础法器耗材'),
('fengdu_general_shop', 'underworld_fengdu', '冥市杂货行', 'general', 'ghost_cash', '回收与供应常见修行材料'),
('fengdu_formation_shop', 'underworld_fengdu', '九曲阵材铺', 'formation', 'ghost_cash', '售卖初阶阵旗与布阵材料')
ON CONFLICT (id) DO NOTHING;

INSERT INTO item_definitions
(id, name, category, quality, max_stack, icon_key, description)
VALUES
('fengdu_warding_talisman', '镇邪符', 'material', 1, 99, 'talisman_warding', '可用于符箓学习与合成的基础符箓材料；实际施符效果由技能系统提供。'),
('fengdu_array_flag', '聚阴阵旗', 'material', 1, 99, 'formation_flag_nether', '布置初阶聚阴阵所需的阵旗材料。')
ON CONFLICT (id) DO NOTHING;

INSERT INTO npc_shop_items (shop_id, item_id, unit_price, stock_quantity, sort_order)
VALUES
('fengdu_weapon_shop', 'starter_iron_sword', 120, NULL, 10),
('fengdu_weapon_shop', 'starter_cloth_cap', 35, NULL, 20),
('fengdu_weapon_shop', 'starter_leather_vest', 75, NULL, 30),
('fengdu_elixir_shop', 'minor_health_pill', 12, NULL, 10),
('fengdu_elixir_shop', 'minor_mana_pill', 15, NULL, 20),
('fengdu_talisman_shop', 'fengdu_warding_talisman', 18, NULL, 10),
('fengdu_general_shop', 'wolf_fang', 8, NULL, 10),
('fengdu_general_shop', 'wolf_pelt', 12, NULL, 20),
('fengdu_formation_shop', 'fengdu_array_flag', 45, NULL, 10)
ON CONFLICT (shop_id, item_id) DO NOTHING;

COMMIT;
