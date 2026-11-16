BEGIN;

-- Race growth profiles describe how a race converts future progression rewards
-- into its natural strengths. Values are weights in basis points (sum=10000),
-- not direct combat multipliers.
CREATE TABLE race_attribute_growth_profiles (
    race_id VARCHAR(64) PRIMARY KEY REFERENCES race_definitions(id) ON DELETE CASCADE,
    strength_weight INTEGER NOT NULL CHECK (strength_weight >= 0),
    constitution_weight INTEGER NOT NULL CHECK (constitution_weight >= 0),
    agility_weight INTEGER NOT NULL CHECK (agility_weight >= 0),
    spirit_weight INTEGER NOT NULL CHECK (spirit_weight >= 0),
    vitality_weight INTEGER NOT NULL CHECK (vitality_weight >= 0),
    CHECK (strength_weight + constitution_weight + agility_weight + spirit_weight + vitality_weight = 10000)
);

INSERT INTO race_attribute_growth_profiles
    (race_id, strength_weight, constitution_weight, agility_weight, spirit_weight, vitality_weight)
VALUES
    ('human', 1800, 1800, 1800, 2800, 1800),
    ('demon', 2400, 1800, 2000, 1600, 2200),
    ('witch', 3000, 2800, 1000, 800, 2400),
    ('dragon', 2600, 2400, 1200, 1600, 2200)
ON CONFLICT (race_id) DO NOTHING;

-- Bloodlines are independent of cultivation systems. A character may inherit
-- more than one bloodline in future; only one is designated as the primary
-- lineage for presentation and baseline racial traits.
CREATE TABLE bloodline_definitions (
    id VARCHAR(96) PRIMARY KEY,
    race_id VARCHAR(64) NOT NULL REFERENCES race_definitions(id),
    name VARCHAR(64) NOT NULL,
    grade SMALLINT NOT NULL DEFAULT 1 CHECK (grade BETWEEN 1 AND 9),
    base_purity INTEGER NOT NULL DEFAULT 1000 CHECK (base_purity BETWEEN 1 AND 10000),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT NOT NULL DEFAULT '',
    UNIQUE (race_id, id)
);
CREATE UNIQUE INDEX uq_race_default_bloodline
    ON bloodline_definitions(race_id) WHERE is_default;

CREATE TABLE bloodline_attribute_modifiers (
    bloodline_id VARCHAR(96) NOT NULL REFERENCES bloodline_definitions(id) ON DELETE CASCADE,
    attribute_key VARCHAR(24) NOT NULL CHECK (
        attribute_key IN ('strength', 'constitution', 'agility', 'spirit', 'vitality')
    ),
    modifier_basis_points INTEGER NOT NULL DEFAULT 0 CHECK (modifier_basis_points BETWEEN -5000 AND 20000),
    PRIMARY KEY (bloodline_id, attribute_key)
);

CREATE TABLE character_bloodlines (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    bloodline_id VARCHAR(96) NOT NULL REFERENCES bloodline_definitions(id),
    purity INTEGER NOT NULL CHECK (purity BETWEEN 1 AND 10000),
    awakening_stage SMALLINT NOT NULL DEFAULT 0 CHECK (awakening_stage BETWEEN 0 AND 9),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    inherited_from_character_id UUID REFERENCES characters(id),
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, bloodline_id),
    CHECK (inherited_from_character_id IS NULL OR inherited_from_character_id <> character_id)
);
CREATE UNIQUE INDEX uq_character_primary_bloodline
    ON character_bloodlines(character_id) WHERE is_primary;
CREATE INDEX idx_character_bloodlines_lineage ON character_bloodlines(bloodline_id);

INSERT INTO bloodline_definitions (id, race_id, name, grade, base_purity, is_default, description) VALUES
    ('human_mortal_lineage', 'human', '先天人族血脉', 1, 1000, TRUE, '以悟性与适应力见长，可兼容多种道统'),
    ('demon_beast_lineage', 'demon', '百兽妖脉', 1, 1500, TRUE, '血脉会随本体族属分化，容易觉醒种族天赋'),
    ('witch_pangu_lineage', 'witch', '盘古遗脉', 2, 1800, TRUE, '重气血、筋骨与肉身本源，适合巫族炼体'),
    ('dragon_true_lineage', 'dragon', '真龙血脉', 2, 2000, TRUE, '重龙躯、鳞甲、龙息与水行法则')
ON CONFLICT (id) DO NOTHING;

INSERT INTO bloodline_attribute_modifiers (bloodline_id, attribute_key, modifier_basis_points)
VALUES
    ('human_mortal_lineage', 'spirit', 500),
    ('human_mortal_lineage', 'agility', 200),
    ('demon_beast_lineage', 'strength', 500),
    ('demon_beast_lineage', 'agility', 300),
    ('witch_pangu_lineage', 'strength', 900),
    ('witch_pangu_lineage', 'constitution', 900),
    ('dragon_true_lineage', 'strength', 700),
    ('dragon_true_lineage', 'constitution', 700),
    ('dragon_true_lineage', 'vitality', 500)
ON CONFLICT (bloodline_id, attribute_key) DO NOTHING;

-- A character can own several techniques, but a technique can only be
-- equipped once in the same slot. Cross-race learning is explicit per race;
-- it is never inferred from the shared Power Tier mapping.
CREATE TABLE cultivation_techniques (
    id VARCHAR(96) PRIMARY KEY,
    system_id VARCHAR(64) NOT NULL REFERENCES cultivation_systems(id),
    name VARCHAR(80) NOT NULL,
    technique_type VARCHAR(24) NOT NULL CHECK (
        technique_type IN ('foundation', 'body', 'spell', 'bloodline', 'movement', 'support')
    ),
    grade SMALLINT NOT NULL DEFAULT 1 CHECK (grade BETWEEN 1 AND 9),
    min_realm_order SMALLINT NOT NULL DEFAULT 1 CHECK (min_realm_order > 0),
    is_cross_race BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT NOT NULL DEFAULT '',
    UNIQUE (system_id, id)
);

CREATE TABLE technique_race_compatibility (
    technique_id VARCHAR(96) NOT NULL REFERENCES cultivation_techniques(id) ON DELETE CASCADE,
    race_id VARCHAR(64) NOT NULL REFERENCES race_definitions(id),
    compatibility VARCHAR(16) NOT NULL CHECK (
        compatibility IN ('native', 'compatible', 'incompatible')
    ),
    efficiency_basis_points INTEGER NOT NULL CHECK (efficiency_basis_points BETWEEN 0 AND 15000),
    unlock_condition TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (technique_id, race_id),
    CHECK (
        (compatibility = 'native' AND efficiency_basis_points = 10000) OR
        (compatibility = 'compatible' AND efficiency_basis_points BETWEEN 1 AND 15000) OR
        (compatibility = 'incompatible' AND efficiency_basis_points = 0)
    )
);

CREATE TABLE character_techniques (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    technique_id VARCHAR(96) NOT NULL REFERENCES cultivation_techniques(id),
    proficiency BIGINT NOT NULL DEFAULT 0 CHECK (proficiency >= 0),
    is_equipped BOOLEAN NOT NULL DEFAULT FALSE,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, technique_id)
);
CREATE INDEX idx_character_techniques_equipped
    ON character_techniques(character_id, is_equipped);

INSERT INTO cultivation_techniques
    (id, system_id, name, technique_type, grade, min_realm_order, is_cross_race, description)
VALUES
    ('human_basic_qi', 'human_immortal_path', '基础吐纳诀', 'foundation', 1, 1, TRUE, '人族入门吐纳法，重灵气感知与周天运转'),
    ('human_sword_intent', 'human_immortal_path', '青云剑诀', 'spell', 2, 2, TRUE, '以灵力御剑，修剑气与剑意'),
    ('human_spirit_guard', 'human_immortal_path', '凝神守一诀', 'support', 2, 2, TRUE, '凝练神识，提升心神防护'),
    ('demon_breath', 'demon_yxiu_path', '吞月纳灵法', 'foundation', 1, 1, TRUE, '吞吐月华与天地灵气，滋养妖丹'),
    ('demon_beast_body', 'demon_yxiu_path', '百兽淬躯术', 'body', 2, 2, TRUE, '借百兽精气强化妖躯'),
    ('demon_instinct', 'demon_yxiu_path', '本命灵觉', 'bloodline', 2, 2, FALSE, '引导血脉觉醒本命感知'),
    ('witch_blood_temper', 'witch_body_path', '祖脉淬血法', 'body', 1, 1, TRUE, '以气血和煞气淬炼肉身'),
    ('witch_totem', 'witch_body_path', '图腾战纹', 'support', 2, 2, FALSE, '以图腾承载部族意志与肉身力量'),
    ('witch_battle_step', 'witch_body_path', '踏山步', 'movement', 2, 2, TRUE, '以强横肉身爆发短距离冲锋'),
    ('dragon_breath', 'dragon_blood_path', '龙息吐纳术', 'foundation', 1, 1, TRUE, '以龙息运转血脉与龙珠本源'),
    ('dragon_scale', 'dragon_blood_path', '玄鳞护体', 'body', 2, 2, TRUE, '凝聚龙鳞之力强化防御'),
    ('dragon_water_law', 'dragon_blood_path', '控水真诀', 'spell', 3, 3, TRUE, '感悟水行法则并驾驭水域')
ON CONFLICT (id) DO NOTHING;

-- Native compatibility is always 100%. Other races must have an explicit
-- compatibility row; the initial cross-race values are conservative examples
-- and can later be tuned by balance data without code changes.
INSERT INTO technique_race_compatibility
    (technique_id, race_id, compatibility, efficiency_basis_points, unlock_condition)
SELECT technique.id, race.id,
       CASE
         WHEN mapping.race_id IS NOT NULL THEN 'native'
         WHEN technique.is_cross_race THEN 'compatible'
         ELSE 'incompatible'
       END,
       CASE
         WHEN mapping.race_id IS NOT NULL THEN 10000
         WHEN technique.is_cross_race THEN 6500
         ELSE 0
       END,
       CASE
         WHEN mapping.race_id IS NOT NULL THEN ''
         WHEN technique.is_cross_race THEN '需要获得跨族传承或满足对应血脉/功法适配条件'
         ELSE '当前种族无法修炼此功法'
       END
FROM cultivation_techniques technique
CROSS JOIN race_definitions race
LEFT JOIN race_cultivation_systems mapping
  ON mapping.race_id = race.id AND mapping.system_id = technique.system_id
ON CONFLICT (technique_id, race_id) DO NOTHING;

-- Existing characters receive their race's default bloodline exactly once.
INSERT INTO character_bloodlines (character_id, bloodline_id, purity, awakening_stage, is_primary)
SELECT character.id, bloodline.id, bloodline.base_purity, 0, TRUE
FROM characters character
JOIN bloodline_definitions bloodline
  ON bloodline.race_id = character.race_id AND bloodline.is_default
ON CONFLICT (character_id, bloodline_id) DO NOTHING;

COMMIT;
