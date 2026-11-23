BEGIN;
DROP INDEX IF EXISTS idx_world_instances_hell_floor;
ALTER TABLE world_instances DROP CONSTRAINT IF EXISTS world_instances_hell_floor_world_check;
ALTER TABLE world_instances DROP COLUMN IF EXISTS hell_floor;
DROP INDEX IF EXISTS idx_character_hell_trial_status;
DROP TABLE IF EXISTS character_hell_trial_progress;
COMMIT;
