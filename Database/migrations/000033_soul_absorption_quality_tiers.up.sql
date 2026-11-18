BEGIN;

-- Quality is authored by the central service. WorldServer supplies only an
-- allow-listed entity kind; it cannot choose a multiplier or attribute reward.
ALTER TABLE soul_absorption_kinds
    ADD COLUMN quality_tier VARCHAR(16) NOT NULL DEFAULT 'common'
        CHECK (quality_tier IN ('common','elite','ancient','mythic')),
    ADD COLUMN progress_units SMALLINT NOT NULL DEFAULT 1
        CHECK (progress_units IN (1,2,4,8));

ALTER TABLE soul_absorption_records
    ADD COLUMN progress_units SMALLINT NOT NULL DEFAULT 1
        CHECK (progress_units IN (1,2,4,8));

ALTER TABLE soul_absorption_records
    DROP CONSTRAINT IF EXISTS soul_absorption_records_attribute_points_awarded_check;
ALTER TABLE soul_absorption_records
    DROP CONSTRAINT IF EXISTS chk_soul_absorption_attribute_points_awarded;
ALTER TABLE soul_absorption_records
    ADD CONSTRAINT chk_soul_absorption_attribute_points_awarded
    CHECK (attribute_points_awarded BETWEEN 0 AND 10);

-- The first quality ladder is intentionally limited to battle souls. Other
-- attributes can receive their own quality ladders after spawn balance data.
INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity,quality_tier,progress_units)
SELECT 'blazing_war_soul_elite','精英炽战残魂',
       '战意凝聚成形的精英魂体，吞噬后提供双倍力量资质成长进度',
       base_energy*2,trait_key,inheritance_attribute,'rare','elite',2
FROM soul_absorption_kinds WHERE id='blazing_war_soul'
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,
    base_energy=EXCLUDED.base_energy,trait_key=EXCLUDED.trait_key,
    inheritance_attribute=EXCLUDED.inheritance_attribute,rarity=EXCLUDED.rarity,
    quality_tier=EXCLUDED.quality_tier,progress_units=EXCLUDED.progress_units;

INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity,quality_tier,progress_units)
SELECT 'blazing_war_soul_ancient','远古炽战残魂',
       '沉眠于古战场的远古战魂，吞噬后提供四倍力量资质成长进度',
       base_energy*4,trait_key,inheritance_attribute,'rare','ancient',4
FROM soul_absorption_kinds WHERE id='blazing_war_soul'
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,
    base_energy=EXCLUDED.base_energy,trait_key=EXCLUDED.trait_key,
    inheritance_attribute=EXCLUDED.inheritance_attribute,rarity=EXCLUDED.rarity,
    quality_tier=EXCLUDED.quality_tier,progress_units=EXCLUDED.progress_units;

INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity,quality_tier,progress_units)
SELECT 'blazing_war_soul_mythic','上古战神残魂',
       '仅在特殊因果中显现的上古战神残魂，吞噬后提供八倍力量资质成长进度',
       base_energy*8,trait_key,inheritance_attribute,'rare','mythic',8
FROM soul_absorption_kinds WHERE id='blazing_war_soul'
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,
    base_energy=EXCLUDED.base_energy,trait_key=EXCLUDED.trait_key,
    inheritance_attribute=EXCLUDED.inheritance_attribute,rarity=EXCLUDED.rarity,
    quality_tier=EXCLUDED.quality_tier,progress_units=EXCLUDED.progress_units;

COMMIT;
