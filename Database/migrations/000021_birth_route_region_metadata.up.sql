BEGIN;

ALTER TABLE reincarnation_birth_routes
    ADD COLUMN region_id VARCHAR(96) NOT NULL DEFAULT '',
    ADD COLUMN region_name VARCHAR(80) NOT NULL DEFAULT '',
    ADD COLUMN region_description TEXT NOT NULL DEFAULT '',
    ADD COLUMN danger_level SMALLINT NOT NULL DEFAULT 1 CHECK (danger_level BETWEEN 1 AND 10),
    ADD COLUMN resource_tags JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(resource_tags) = 'array'),
    ADD COLUMN exploration_points JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(exploration_points) = 'array'),
    ADD COLUMN race_affinity JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(race_affinity) = 'object');

UPDATE reincarnation_birth_routes
SET region_id = 'qingyun_misty_stream',
    region_name = '灵溪谷',
    region_description = '青云山脉灵溪上游，地势开阔，灵气平和，适合初入世界的修行者。',
    danger_level = 2,
    resource_tags = '["清灵草","溪涧灵砂","低阶灵木"]'::jsonb,
    exploration_points = '[
      {"id":"misty_stream_source","name":"灵溪源头","description":"调查溪水灵气异常的源头。","recommended_power":1},
      {"id":"old_stone_bridge","name":"古石桥","description":"桥下有被水流冲刷出的旧式符纹。","recommended_power":1},
      {"id":"spirit_herb_slope","name":"灵草坡","description":"采集常见灵草，留意守护灵兽。","recommended_power":1}
    ]'::jsonb,
    race_affinity = '{
      "human":{"rating":"excellent","description":"灵气稳定，适合人族感悟基础吐纳与经脉运行。"},
      "demon":{"rating":"good","description":"灵气中夹杂少量兽息，可供妖族适应人形与本相切换。"}
    }'::jsonb
WHERE id = 'qingyun_human_misty_valley';

UPDATE reincarnation_birth_routes
SET region_id = 'qingyun_beast_ridge',
    region_name = '百兽岭',
    region_description = '青云山脉外围古林山岭，灵气与兽息交汇，地形复杂，野兽活动频繁。',
    danger_level = 4,
    resource_tags = '["妖纹木","兽血藤","荒狼獠牙"]'::jsonb,
    exploration_points = '[
      {"id":"beast_totem_rock","name":"兽纹岩","description":"岩壁残留古老兽纹，可追查山岭来历。","recommended_power":2},
      {"id":"wind_howl_pass","name":"啸风隘口","description":"风口常有低阶妖兽出没，适合熟悉战斗。","recommended_power":2},
      {"id":"ancient_tree_hollow","name":"古木空洞","description":"巨树内部似乎藏有旧时代遗物。","recommended_power":3}
    ]'::jsonb,
    race_affinity = '{
      "human":{"rating":"fair","description":"兽群活动频繁，人族需要谨慎探索并准备基础防具。"},
      "demon":{"rating":"excellent","description":"兽息浓郁，有助妖族感应血脉与适应本相。"}
    }'::jsonb
WHERE id = 'qingyun_demon_beast_ridge';

CREATE INDEX idx_reincarnation_birth_routes_region
    ON reincarnation_birth_routes(region_id, enabled);

COMMIT;
