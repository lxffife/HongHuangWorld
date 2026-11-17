BEGIN;
DROP TABLE IF EXISTS item_use_events;
DELETE FROM item_definitions WHERE id IN ('starter_iron_sword','starter_cloth_cap','starter_leather_vest','starter_trousers','starter_travel_boots','starter_wooden_charm','minor_health_pill','minor_mana_pill');
COMMIT;
