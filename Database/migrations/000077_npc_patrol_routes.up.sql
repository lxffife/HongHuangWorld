BEGIN;

ALTER TABLE world_npc_definitions
    ADD COLUMN behavior_profile VARCHAR(32) NOT NULL DEFAULT 'stationary'
        CHECK (behavior_profile IN ('stationary','guard_patrol','resident_route','vendor_shift')),
    ADD COLUMN patrol_route JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(patrol_route) = 'object');

ALTER TABLE world_npc_definitions
    ADD CONSTRAINT world_npc_guard_patrol_route_check
    CHECK (behavior_profile <> 'guard_patrol'
           OR jsonb_typeof(patrol_route->'waypoints') = 'array');

-- The reincarnation-hall guard patrols a compact loop around the entrance.
-- This keeps the key interaction NPC in its authored service area.
UPDATE world_npc_definitions
SET behavior_profile = 'guard_patrol',
    patrol_route = '{
      "waypoints": [
        {"x": -3.0, "y": 0.0, "z": 10.0, "wait_seconds": 2.5},
        {"x": 3.0, "y": 0.0, "z": 10.0, "wait_seconds": 2.0},
        {"x": 3.0, "y": 0.0, "z": 16.0, "wait_seconds": 2.5},
        {"x": -3.0, "y": 0.0, "z": 16.0, "wait_seconds": 2.0}
      ],
      "speed_mps": 1.15,
      "default_wait_seconds": 1.5,
      "phase_offset_seconds": 0.0,
      "loop": true
    }'::jsonb,
    updated_at = now()
WHERE id = 'fengdu_reincarnation_guard'
  AND world_id = 'underworld_fengdu';

COMMIT;
