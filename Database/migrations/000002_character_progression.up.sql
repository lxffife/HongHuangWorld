BEGIN;

-- A character's cultivation path is selected by race, but systems remain
-- independent so future talents, bloodlines and inherited techniques can
-- unlock cross-race paths without changing the core progression model.
CREATE TABLE race_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(48) NOT NULL,
    description TEXT NOT NULL DEFAULT ''
);

CREATE TABLE cultivation_systems (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE race_cultivation_systems (
    race_id VARCHAR(64) NOT NULL REFERENCES race_definitions(id),
    system_id VARCHAR(64) NOT NULL REFERENCES cultivation_systems(id),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (race_id, system_id)
);
CREATE UNIQUE INDEX uq_race_default_cultivation_system
    ON race_cultivation_systems(race_id) WHERE is_default;

-- A power tier is a comparison aid only. It is not a claim that two realms
-- are identical in combat style, resources, difficulty or abilities.
CREATE TABLE power_tiers (
    id VARCHAR(32) PRIMARY KEY,
    tier_order SMALLINT NOT NULL UNIQUE CHECK (tier_order > 0),
    name VARCHAR(48) NOT NULL,
    description TEXT NOT NULL DEFAULT ''
);

CREATE TABLE cultivation_realms (
    id VARCHAR(96) PRIMARY KEY,
    system_id VARCHAR(64) NOT NULL REFERENCES cultivation_systems(id),
    name VARCHAR(48) NOT NULL,
    realm_order SMALLINT NOT NULL CHECK (realm_order > 0),
    max_stage SMALLINT NOT NULL DEFAULT 9 CHECK (max_stage > 0),
    required_cultivation BIGINT NOT NULL DEFAULT 0 CHECK (required_cultivation >= 0),
    breakthrough_description TEXT NOT NULL DEFAULT '',
    UNIQUE (system_id, realm_order),
    UNIQUE (system_id, id)
);

CREATE TABLE cultivation_stages (
    realm_id VARCHAR(96) NOT NULL REFERENCES cultivation_realms(id) ON DELETE CASCADE,
    stage_order SMALLINT NOT NULL CHECK (stage_order > 0),
    name VARCHAR(32) NOT NULL,
    PRIMARY KEY (realm_id, stage_order)
);

CREATE TABLE realm_power_mappings (
    realm_id VARCHAR(96) PRIMARY KEY REFERENCES cultivation_realms(id) ON DELETE CASCADE,
    power_tier_id VARCHAR(32) NOT NULL REFERENCES power_tiers(id),
    comparison_note TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_realm_power_tier ON realm_power_mappings(power_tier_id);

INSERT INTO race_definitions (id, name, description) VALUES
    ('human', '人族', '以悟道、炼气、凝结金丹与元神为主的修仙体系'),
    ('demon', '妖族', '以开灵、化形、凝聚妖丹与淬炼妖魂为主的妖修体系'),
    ('witch', '巫族', '以血脉、肉身、图腾和天地煞气淬炼为主的炼体体系'),
    ('dragon', '龙族', '以龙族血脉、龙躯成长、龙珠与法则传承为主的血脉体系')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cultivation_systems (id, name, description) VALUES
    ('human_immortal_path', '人族仙道', '重悟性、灵根、功法与元神，擅长法术、阵法和多样化道统'),
    ('demon_y妖_path', '妖族妖修', '重血脉、妖躯、妖丹与天赋神通，种族差异会显著影响成长路线'),
    ('witch_body_path', '巫族炼体', '重肉身、血脉、图腾与煞气，不以传统元神修炼作为核心'),
    ('dragon_blood_path', '龙族血脉', '重龙族血脉纯度、龙躯、龙珠和法则传承，成长伴随形态与天赋变化')
ON CONFLICT (id) DO NOTHING;

INSERT INTO race_cultivation_systems (race_id, system_id, is_default) VALUES
    ('human', 'human_immortal_path', TRUE),
    ('demon', 'demon_y妖_path', TRUE),
    ('witch', 'witch_body_path', TRUE),
    ('dragon', 'dragon_blood_path', TRUE)
ON CONFLICT (race_id, system_id) DO NOTHING;

INSERT INTO power_tiers (id, tier_order, name, description) VALUES
    ('tier_1', 1, '初入修行', '开始超越凡俗的综合实力参考层级'),
    ('tier_2', 2, '脱凡立基', '形成稳定的超凡力量体系'),
    ('tier_3', 3, '凝聚本源', '力量核心初步成形'),
    ('tier_4', 4, '神魂/血脉蜕变', '生命形态或力量本源出现显著蜕变'),
    ('tier_5', 5, '掌控神通', '开始稳定掌握高阶神通或领域能力'),
    ('tier_6', 6, '法则入门', '开始触及世界法则或更高层次本源'),
    ('tier_7', 7, '法则精进', '对本源力量具有较强掌控力'),
    ('tier_8', 8, '大道合一', '自身体系趋于圆融并触及大道'),
    ('tier_9', 9, '渡劫超脱', '具备冲击更高生命层次的资格')
ON CONFLICT (id) DO NOTHING;

-- Each race has its own realm names and descriptions. The shared tier is only
-- a broad matchmaking/reference band; combat balance remains system-specific.
INSERT INTO cultivation_realms (id, system_id, name, realm_order, max_stage, required_cultivation, breakthrough_description) VALUES
    ('human_qi_refining', 'human_immortal_path', '炼气期', 1, 9, 0, '感应灵气，引气入体'),
    ('human_foundation', 'human_immortal_path', '筑基期', 2, 9, 10000, '筑成道基，稳定灵力循环'),
    ('human_golden_core', 'human_immortal_path', '金丹期', 3, 9, 100000, '凝结金丹，形成力量核心'),
    ('human_nascent_soul', 'human_immortal_path', '元婴期', 4, 9, 1000000, '金丹化婴，元神初成'),
    ('human_spirit_transformation', 'human_immortal_path', '化神期', 5, 9, 10000000, '元神壮大，神念与神通蜕变'),
    ('human_void_refinement', 'human_immortal_path', '炼虚期', 6, 9, 100000000, '感悟虚空与天地法则'),
    ('human_body_integration', 'human_immortal_path', '合体期', 7, 9, 1000000000, '元神与肉身进一步合一'),
    ('human_mahayana', 'human_immortal_path', '大乘期', 8, 9, 10000000000, '道行圆融，准备渡劫'),
    ('human_tribulation', 'human_immortal_path', '渡劫期', 9, 9, 100000000000, '经历天劫，冲击更高生命层次'),

    ('demon_open_spirit', 'demon_y妖_path', '开灵境', 1, 9, 0, '开启灵智，感应天地灵气'),
    ('demon_transformation', 'demon_y妖_path', '化形境', 2, 9, 10000, '凝练妖躯，初步化形'),
    ('demon_core', 'demon_y妖_path', '妖丹境', 3, 9, 100000, '凝聚妖丹，形成妖力核心'),
    ('demon_soul', 'demon_y妖_path', '妖魂境', 4, 9, 1000000, '妖丹孕魂，神识大幅成长'),
    ('demon_divinity', 'demon_y妖_path', '妖神境', 5, 9, 10000000, '血脉与妖魂蜕变，觉醒强大神通'),
    ('demon_domain', 'demon_y妖_path', '妖域境', 6, 9, 100000000, '以妖力构筑自身领域'),
    ('demon_heaven', 'demon_y妖_path', '通天境', 7, 9, 1000000000, '妖道通天，掌握天地伟力'),
    ('demon_sacred', 'demon_y妖_path', '妖圣境', 8, 9, 10000000000, '妖道大成，成为一方妖圣'),
    ('demon_tribulation', 'demon_y妖_path', '渡劫境', 9, 9, 100000000000, '渡过妖族大劫，冲击更高层次'),

    ('witch_tempering', 'witch_body_path', '淬体境', 1, 9, 0, '以气血和天地煞气淬炼肉身'),
    ('witch_bronze', 'witch_body_path', '铜身境', 2, 9, 10000, '筋骨如铜，肉身强度大幅提升'),
    ('witch_silver', 'witch_body_path', '银身境', 3, 9, 100000, '气血凝练，肉身本源稳固'),
    ('witch_gold', 'witch_body_path', '金身境', 4, 9, 1000000, '肉身蜕变，觉醒更强血脉之力'),
    ('witch_great', 'witch_body_path', '大巫境', 5, 9, 10000000, '血脉显化，掌握强大巫术'),
    ('witch_ancestral', 'witch_body_path', '祖巫境', 6, 9, 100000000, '血脉返祖，触及祖巫本源'),
    ('witch_domain', 'witch_body_path', '领域境', 7, 9, 1000000000, '以肉身与图腾意志开辟领域'),
    ('witch_sacred', 'witch_body_path', '巫圣境', 8, 9, 10000000000, '巫道大成，肉身近乎不朽'),
    ('witch_origin', 'witch_body_path', '返祖归源境', 9, 9, 100000000000, '血脉返祖至源头，冲击更高生命层次'),

    ('dragon_initial_blood', 'dragon_blood_path', '初血境', 1, 9, 0, '觉醒龙族血脉，强化龙躯'),
    ('dragon_jiao', 'dragon_blood_path', '蛟血境', 2, 9, 10000, '血脉向真龙蜕变，龙躯初成'),
    ('dragon_true', 'dragon_blood_path', '真龙境', 3, 9, 100000, '真龙血脉稳定，凝聚龙族本源'),
    ('dragon_pearl', 'dragon_blood_path', '龙珠境', 4, 9, 1000000, '凝成龙珠，驾驭本命神通'),
    ('dragon_king', 'dragon_blood_path', '龙王境', 5, 9, 10000000, '血脉与龙珠蜕变，统御一方水域'),
    ('dragon_lord', 'dragon_blood_path', '龙君境', 6, 9, 100000000, '掌握龙族法则与领域'),
    ('dragon_emperor', 'dragon_blood_path', '龙皇境', 7, 9, 1000000000, '龙族本源大成，统御万龙'),
    ('dragon_ancestral', 'dragon_blood_path', '祖龙境', 8, 9, 10000000000, '血脉追溯祖龙，触及龙族大道'),
    ('dragon_tribulation', 'dragon_blood_path', '化祖境', 9, 9, 100000000000, '血脉与大道归一，冲击更高生命层次')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cultivation_stages (realm_id, stage_order, name)
SELECT realm.id, stage.stage_order, stage.name
FROM cultivation_realms realm
CROSS JOIN (VALUES
    (1, '一重'), (2, '二重'), (3, '三重'),
    (4, '四重'), (5, '五重'), (6, '六重'),
    (7, '七重'), (8, '八重'), (9, '九重')
) AS stage(stage_order, name)
ON CONFLICT (realm_id, stage_order) DO NOTHING;

INSERT INTO realm_power_mappings (realm_id, power_tier_id, comparison_note)
SELECT realm.id, tier.id,
       '同一参考层级不代表战斗能力相同；需结合血脉、肉身、功法、神通、装备与战斗环境评估。'
FROM cultivation_realms realm
JOIN power_tiers tier ON tier.tier_order = realm.realm_order
ON CONFLICT (realm_id) DO NOTHING;

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
    system_id VARCHAR(64) NOT NULL REFERENCES cultivation_systems(id),
    experience BIGINT NOT NULL DEFAULT 0 CHECK (experience >= 0),
    cultivation BIGINT NOT NULL DEFAULT 0 CHECK (cultivation >= 0),
    realm_id VARCHAR(96) NOT NULL REFERENCES cultivation_realms(id),
    realm_stage SMALLINT NOT NULL DEFAULT 1 CHECK (realm_stage > 0),
    unspent_attribute_points INTEGER NOT NULL DEFAULT 0 CHECK (unspent_attribute_points >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE character_reward_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id UUID NOT NULL REFERENCES server_registry(id),
    character_id UUID NOT NULL REFERENCES characters(id),
    event_id UUID NOT NULL,
    experience BIGINT NOT NULL DEFAULT 0 CHECK (experience >= 0),
    cultivation BIGINT NOT NULL DEFAULT 0 CHECK (cultivation >= 0),
    attribute_points INTEGER NOT NULL DEFAULT 0 CHECK (attribute_points >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (server_id, event_id),
    CHECK (experience > 0 OR cultivation > 0 OR attribute_points > 0)
);
CREATE INDEX idx_character_reward_events_character ON character_reward_events(character_id, created_at DESC);

-- Backfill characters created before this migration using their race's default
-- path. Characters without a recognized race fall back to the human path.
INSERT INTO character_attributes (character_id)
SELECT id FROM characters
ON CONFLICT (character_id) DO NOTHING;

INSERT INTO character_progression (character_id, system_id, realm_id)
SELECT c.id, COALESCE(mapping.system_id, 'human_immortal_path'), realm.id
FROM characters c
LEFT JOIN race_cultivation_systems mapping
  ON mapping.race_id = COALESCE(NULLIF(c.race_id, ''), 'human') AND mapping.is_default
JOIN cultivation_realms realm
  ON realm.system_id = COALESCE(mapping.system_id, 'human_immortal_path') AND realm.realm_order = 1
ON CONFLICT (character_id) DO NOTHING;

COMMIT;
