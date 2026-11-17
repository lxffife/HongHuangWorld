BEGIN;
DELETE FROM world_exploration_events
WHERE id IN ('fengdu_lantern_memory','wangchuan_past_echo','naihe_bridge_ancient_oath','reincarnation_hall_cycle');
DELETE FROM world_exploration_points
WHERE id IN ('fengdu_gate_soul_lantern','forgotten_river_echo_stone','naihe_bridge_soul_mark','reincarnation_hall_tablet');
COMMIT;
