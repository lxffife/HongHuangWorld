BEGIN;
UPDATE world_exploration_events SET enabled=FALSE WHERE id='fengdu_ancient_battlefield';
UPDATE world_exploration_points SET enabled=FALSE WHERE id='fengdu_ancient_battlefield';
UPDATE soul_absorption_kinds SET enabled=FALSE WHERE id='ancient_battlefield_god_soul';
COMMIT;
