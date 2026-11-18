BEGIN;
ALTER TABLE world_exploration_events DROP COLUMN IF EXISTS choices;
COMMIT;
