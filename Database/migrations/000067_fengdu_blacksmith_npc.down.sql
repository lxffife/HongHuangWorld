BEGIN;
DELETE FROM world_npc_definitions WHERE id='fengdu_blacksmith';
ALTER TABLE world_npc_definitions DROP CONSTRAINT IF EXISTS world_npc_definitions_npc_type_check;
ALTER TABLE world_npc_definitions ADD CONSTRAINT world_npc_definitions_npc_type_check
 CHECK (npc_type IN ('guide','trial_master','judge','soup_keeper','guard'));
ALTER TABLE world_npc_definitions DROP CONSTRAINT IF EXISTS world_npc_definitions_interaction_type_check;
ALTER TABLE world_npc_definitions ADD CONSTRAINT world_npc_definitions_interaction_type_check
 CHECK (interaction_type IN ('dialogue','soul_trials','soul_judgement','reincarnation_guidance','world_guard'));
COMMIT;
