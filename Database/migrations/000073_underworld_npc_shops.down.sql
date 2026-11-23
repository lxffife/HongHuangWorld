BEGIN;
DROP TABLE IF EXISTS npc_shop_purchase_events;
DROP TABLE IF EXISTS npc_shop_items;
DROP TABLE IF EXISTS npc_shop_definitions;
DELETE FROM item_definitions WHERE id IN ('fengdu_warding_talisman', 'fengdu_array_flag');
COMMIT;
