BEGIN;
ALTER TABLE item_definitions DROP CONSTRAINT IF EXISTS item_weapon_type_valid;
ALTER TABLE item_definitions DROP COLUMN IF EXISTS weapon_type;
COMMIT;