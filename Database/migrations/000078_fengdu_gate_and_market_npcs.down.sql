BEGIN;

DELETE FROM world_npc_definitions
WHERE world_id='underworld_fengdu'
  AND id IN (
    'fengdu_south_gate_guard',
    'fengdu_ghost_market_vendor_west',
    'fengdu_ghost_market_vendor_east'
  );

COMMIT;
