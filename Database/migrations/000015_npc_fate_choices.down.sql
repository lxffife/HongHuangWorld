BEGIN;
UPDATE world_npc_definitions
SET dialogue = dialogue - 'choices', updated_at = now()
WHERE id = 'fengdu_judge';
DROP TABLE IF EXISTS soul_fate_choice_claims;
COMMIT;
