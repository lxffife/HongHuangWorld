BEGIN;
DELETE FROM monster_loot_entries WHERE item_id IN ('wolfbone_short_sword','wolfhide_vest');
DELETE FROM item_definitions WHERE id IN ('wolfbone_short_sword','wolfhide_vest');
ALTER TABLE character_equipment DROP COLUMN IF EXISTS item_instance_id;
DROP TABLE IF EXISTS character_item_instances;
ALTER TABLE ground_drops DROP COLUMN IF EXISTS item_instance_id;
DROP TABLE IF EXISTS item_instances;
DROP TABLE IF EXISTS equipment_affix_definitions;
COMMIT;
