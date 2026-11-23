BEGIN;
-- Shop items may already be owned by characters. Preserve item definitions and
-- inventory records when rolling back the shop feature.
DROP TABLE IF EXISTS npc_shop_purchase_events;
DROP TABLE IF EXISTS npc_shop_items;
DROP TABLE IF EXISTS npc_shop_definitions;
COMMIT;
