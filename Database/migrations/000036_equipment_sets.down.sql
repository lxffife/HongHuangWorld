BEGIN;
DROP INDEX IF EXISTS idx_item_definitions_equipment_set;
ALTER TABLE item_definitions DROP COLUMN IF EXISTS equipment_set_id;
DROP TABLE IF EXISTS equipment_sets;
COMMIT;
