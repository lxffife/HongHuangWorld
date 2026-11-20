BEGIN;

ALTER TABLE item_definitions
    ADD COLUMN weapon_type VARCHAR(24);

-- Existing weapon catalog entries predate explicit weapon metadata.
-- Preserve the current starter sword as a sword; future weapon entries must declare a type.
UPDATE item_definitions
SET weapon_type = 'sword'
WHERE id = 'starter_iron_sword' AND equipment_slot = 'weapon';

-- Fail safely if a custom weapon exists without an explicit classification.
-- Add its weapon_type before applying this migration rather than guessing from its name.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM item_definitions WHERE equipment_slot = 'weapon' AND weapon_type IS NULL) THEN
        RAISE EXCEPTION 'weapon_type is missing for one or more weapon items; classify them before applying migration 000049';
    END IF;
END;
$$;

ALTER TABLE item_definitions
    ADD CONSTRAINT item_weapon_type_valid CHECK (
        (equipment_slot = 'weapon' AND weapon_type IN
            ('sword', 'spear', 'bow', 'staff', 'dagger', 'axe', 'hammer', 'focus'))
        OR (equipment_slot IS DISTINCT FROM 'weapon' AND weapon_type IS NULL)
    );

COMMENT ON COLUMN item_definitions.weapon_type IS
    'Explicit combat weapon category; required only for weapon-slot equipment.';

COMMIT;