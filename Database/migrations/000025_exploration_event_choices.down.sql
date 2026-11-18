BEGIN;
ALTER TABLE soul_exploration_event_claims DROP COLUMN IF EXISTS choice_id;
ALTER TABLE world_exploration_events DROP COLUMN IF EXISTS choices;
COMMIT;
