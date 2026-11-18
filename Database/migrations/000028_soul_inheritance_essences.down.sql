BEGIN;
DROP INDEX IF EXISTS idx_soul_absorption_pending_choice;
ALTER TABLE soul_absorption_records DROP CONSTRAINT IF EXISTS chk_absorption_selected_attribute;
ALTER TABLE soul_absorption_records DROP COLUMN IF EXISTS selected_at;
ALTER TABLE soul_absorption_records DROP COLUMN IF EXISTS selected_attribute;
DELETE FROM soul_absorption_kinds WHERE id IN
 ('blazing_war_soul','ironbone_beast_soul','gale_wraith','spirit_scholar_wisp','life_ancient_soul','faceless_essence');
UPDATE soul_absorption_kinds SET inheritance_attribute=NULL,rarity='common'
 WHERE id IN ('beast_spirit','battle_spirit');
ALTER TABLE soul_absorption_kinds DROP CONSTRAINT IF EXISTS chk_soul_absorption_attribute;
ALTER TABLE soul_absorption_kinds DROP COLUMN IF EXISTS inheritance_attribute;
ALTER TABLE soul_absorption_kinds DROP COLUMN IF EXISTS rarity;
DROP TABLE IF EXISTS soul_inheritance_attributes;
COMMIT;
