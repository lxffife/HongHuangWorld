BEGIN;
ALTER TABLE character_equipment DROP COLUMN IF EXISTS item_instance_id;
DROP TABLE IF EXISTS character_item_instances;
ALTER TABLE ground_drops DROP COLUMN IF EXISTS item_instance_id;
DROP TABLE IF EXISTS item_instances;
DROP TABLE IF EXISTS equipment_affix_definitions;
COMMIT;
