BEGIN;

DELETE FROM currency_issuance_policies
WHERE world_id = 'underworld_fengdu'
  AND source_type = 'monster_kill'
  AND currency_id IN ('ghost_cash', 'nether_stone');

UPDATE currency_world_rules
SET issue_enabled = FALSE
WHERE world_id = 'underworld_fengdu' AND currency_id = 'nether_stone';

COMMIT;
