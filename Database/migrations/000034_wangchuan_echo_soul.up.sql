BEGIN;

-- The Wangchuan echo wisp is a rare, soul-specific encounter. Its catalogue
-- values are inherited from the existing spirit wisp; the backend alone
-- assigns the ancient quality multiplier.
INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity,quality_tier,progress_units)
SELECT 'wangchuan_echo_wisp','忘川回音灵识',
       '回应忘川回音后显现的古老灵识魂体，提供四倍灵力资质成长进度',
       base_energy*4,trait_key,inheritance_attribute,'rare','ancient',4
FROM soul_absorption_kinds
WHERE id='spirit_scholar_wisp'
ON CONFLICT (id) DO UPDATE SET
    name=EXCLUDED.name,
    description=EXCLUDED.description,
    base_energy=EXCLUDED.base_energy,
    trait_key=EXCLUDED.trait_key,
    inheritance_attribute=EXCLUDED.inheritance_attribute,
    rarity=EXCLUDED.rarity,
    quality_tier=EXCLUDED.quality_tier,
    progress_units=EXCLUDED.progress_units;

COMMIT;
