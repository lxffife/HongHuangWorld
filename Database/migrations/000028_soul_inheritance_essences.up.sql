BEGIN;

-- Reincarnation attributes are soul-owned potential, not current-body stats.
CREATE TABLE soul_inheritance_attributes (
    soul_id UUID PRIMARY KEY REFERENCES souls(id) ON DELETE CASCADE,
    strength BIGINT NOT NULL DEFAULT 0 CHECK (strength >= 0),
    constitution BIGINT NOT NULL DEFAULT 0 CHECK (constitution >= 0),
    agility BIGINT NOT NULL DEFAULT 0 CHECK (agility >= 0),
    spirit BIGINT NOT NULL DEFAULT 0 CHECK (spirit >= 0),
    vitality BIGINT NOT NULL DEFAULT 0 CHECK (vitality >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO soul_inheritance_attributes (soul_id)
SELECT id FROM souls ON CONFLICT (soul_id) DO NOTHING;

ALTER TABLE soul_absorption_kinds
    ADD COLUMN inheritance_attribute VARCHAR(24),
    ADD COLUMN rarity VARCHAR(16) NOT NULL DEFAULT 'common'
        CHECK (rarity IN ('common','uncommon','rare'));
ALTER TABLE soul_absorption_kinds
    ADD CONSTRAINT chk_soul_absorption_attribute
    CHECK (inheritance_attribute IS NULL OR inheritance_attribute IN
        ('strength','constitution','agility','spirit','vitality'));

UPDATE soul_absorption_kinds SET inheritance_attribute='constitution',rarity='uncommon'
 WHERE id='beast_spirit';
UPDATE soul_absorption_kinds SET inheritance_attribute='strength',rarity='uncommon'
 WHERE id='battle_spirit';

INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity)
VALUES
 ('blazing_war_soul','炽战残魂','残留战斗意志与爆发本能，强化来世力量资质',12,'strength_affinity','strength','uncommon'),
 ('ironbone_beast_soul','铁骨兽魂','蕴含坚韧筋骨与厚重血气，强化来世体质资质',12,'constitution_affinity','constitution','uncommon'),
 ('gale_wraith','疾风游魂','残留迅捷身法与风行记忆，强化来世敏捷资质',10,'agility_affinity','agility','uncommon'),
 ('spirit_scholar_wisp','灵识游魂','蕴含灵性与术法感悟，强化来世灵力资质',12,'spirit_affinity','spirit','uncommon'),
 ('life_ancient_soul','生机古魂','残留旺盛生命本源，强化来世气血资质',14,'vitality_affinity','vitality','rare'),
 ('faceless_essence','无相灵魄','极其稀有的无属性魂质，吸收后可由玩家自由指定一项来世资质',20,'faceless_affinity',NULL,'rare')
ON CONFLICT (id) DO UPDATE SET
 name=EXCLUDED.name,description=EXCLUDED.description,base_energy=EXCLUDED.base_energy,
 trait_key=EXCLUDED.trait_key,inheritance_attribute=EXCLUDED.inheritance_attribute,rarity=EXCLUDED.rarity;

ALTER TABLE soul_absorption_records
    ADD COLUMN selected_attribute VARCHAR(24),
    ADD COLUMN selected_at TIMESTAMPTZ,
    ADD CONSTRAINT chk_absorption_selected_attribute
    CHECK (selected_attribute IS NULL OR selected_attribute IN
        ('strength','constitution','agility','spirit','vitality'));

CREATE INDEX idx_soul_absorption_pending_choice
    ON soul_absorption_records(soul_id,created_at)
    WHERE absorption_kind_id='faceless_essence' AND selected_at IS NULL;

COMMIT;
