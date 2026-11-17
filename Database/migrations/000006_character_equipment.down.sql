BEGIN;
DROP TABLE IF EXISTS character_equipment;
DROP TRIGGER IF EXISTS trg_item_type_from_category ON item_definitions;
DROP FUNCTION IF EXISTS sync_item_type_from_category();
ALTER TABLE item_definitions
    DROP CONSTRAINT IF EXISTS item_equipment_slot_required,
    DROP COLUMN IF EXISTS use_effect,
    DROP COLUMN IF EXISTS base_stats,
    DROP COLUMN IF EXISTS equipment_slot,
    DROP COLUMN IF EXISTS item_type;
COMMIT;
