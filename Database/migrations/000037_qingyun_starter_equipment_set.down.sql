BEGIN;
UPDATE item_definitions SET equipment_set_id=NULL WHERE equipment_set_id='qingyun_starter_set';
DELETE FROM equipment_sets WHERE id='qingyun_starter_set';
COMMIT;
