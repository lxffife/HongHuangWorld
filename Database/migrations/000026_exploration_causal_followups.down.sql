BEGIN;

DELETE FROM world_exploration_events WHERE id='fengdu_lantern_old_shadow';
DELETE FROM world_exploration_points WHERE id='fengdu_lantern_shadow_trace';

ALTER TABLE world_exploration_events
    DROP CONSTRAINT IF EXISTS chk_world_exploration_event_prerequisite_pair,
    DROP COLUMN IF EXISTS required_choice_id,
    DROP COLUMN IF EXISTS required_event_id;

COMMIT;
