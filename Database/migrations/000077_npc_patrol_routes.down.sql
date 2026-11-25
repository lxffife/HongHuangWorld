BEGIN;

UPDATE world_npc_definitions
SET behavior_profile = 'stationary',
    patrol_route = '{}'::jsonb,
    updated_at = now()
WHERE id = 'fengdu_reincarnation_guard'
  AND world_id = 'underworld_fengdu';

ALTER TABLE world_npc_definitions
    DROP CONSTRAINT IF EXISTS world_npc_guard_patrol_route_check;
ALTER TABLE world_npc_definitions
    DROP COLUMN patrol_route,
    DROP COLUMN behavior_profile;

COMMIT;
