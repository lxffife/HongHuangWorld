BEGIN;

ALTER TABLE item_definitions
    ADD COLUMN weapon_type VARCHAR(24);

-- Existing weapon catalog entries predate explicit weapon metadata.
-- Preserve the current starter sword as a sword; future weapon entries must declare a type.
UPDATE item_definitions
SET weapon_type = CASE
    WHEN id LIKE '%spear%' OR name LIKE '%枪%' OR name LIKE '%矛%' THEN 'spear'
    WHEN id LIKE '%bow%' OR name LIKE '%弓%' THEN 'bow'
    WHEN id LIKE '%staff%' OR id LIKE '%wand%' OR name LIKE '%法杖%' OR name LIKE '%拂尘%' THEN 'staff'
    WHEN id LIKE '%axe%' OR name LIKE '%斧%' THEN 'axe'
    WHEN id LIKE '%hammer%' OR name LIKE '%锤%' THEN 'hammer'
    WHEN id LIKE '%dagger%' OR name LIKE '%匕首%' THEN 'dagger'
    WHEN id LIKE '%focus%' OR name LIKE '%法器%' THEN 'focus'
    ELSE 'sword'
END
WHERE equipment_slot = 'weapon';

ALTER TABLE item_definitions
    ADD CONSTRAINT item_weapon_type_valid CHECK (
        (equipment_slot = 'weapon' AND weapon_type IN
            ('sword', 'spear', 'bow', 'staff', 'dagger', 'axe', 'hammer', 'focus'))
        OR (equipment_slot IS DISTINCT FROM 'weapon' AND weapon_type IS NULL)
    );

COMMENT ON COLUMN item_definitions.weapon_type IS
    'Explicit combat weapon category; required only for weapon-slot equipment.';

COMMIT;