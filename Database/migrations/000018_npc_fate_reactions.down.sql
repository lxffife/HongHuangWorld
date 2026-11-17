BEGIN;

UPDATE world_npc_definitions
SET dialogue = dialogue - 'fate_reactions', updated_at = now()
WHERE id IN ('fengdu_judge', 'fengdu_mengpo');

COMMIT;
