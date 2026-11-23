BEGIN;
DROP TABLE IF EXISTS ground_drop_eligible_characters;
ALTER TABLE parties
  DROP COLUMN IF EXISTS material_loot_mode,
  DROP COLUMN IF EXISTS equipment_loot_mode,
  DROP COLUMN IF EXISTS material_loot_cursor,
  DROP COLUMN IF EXISTS equipment_loot_cursor;
COMMIT;
