BEGIN;
DROP TABLE IF EXISTS equipment_enhancement_events;
DROP TABLE IF EXISTS equipment_enhancement_rules;
ALTER TABLE item_instances DROP COLUMN IF EXISTS enhancement_level;
COMMIT;
