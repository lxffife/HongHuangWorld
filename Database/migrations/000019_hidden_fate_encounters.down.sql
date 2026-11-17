BEGIN;

UPDATE world_npc_definitions
SET dialogue = dialogue - 'fate_encounters', updated_at = now()
WHERE id = 'fengdu_mengpo';

DROP TABLE IF EXISTS soul_fate_encounter_claims;

COMMIT;
