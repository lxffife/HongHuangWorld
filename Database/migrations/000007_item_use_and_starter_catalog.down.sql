BEGIN;
-- Preserve catalog rows that may already be referenced by player inventories.
DROP TABLE IF EXISTS item_use_events;
COMMIT;
