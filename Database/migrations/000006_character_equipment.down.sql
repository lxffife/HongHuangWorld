BEGIN;
DROP TABLE IF EXISTS character_equipment;
ALTER TABLE item_definitions
    DROP CONSTRAINT IF EXISTS item_equipment_slot_required,
    DROP COLUMN IF EXISTS use_effect,
    DROP COLUMN IF EXISTS base_stats,
    DROP COLUMN IF EXISTS equipment_slot,
    DROP COLUMN IF EXISTS item_type;
COMMIT;
