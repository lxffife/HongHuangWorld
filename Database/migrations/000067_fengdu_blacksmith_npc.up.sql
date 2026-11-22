BEGIN;
ALTER TABLE world_npc_definitions DROP CONSTRAINT IF EXISTS world_npc_definitions_npc_type_check;
ALTER TABLE world_npc_definitions ADD CONSTRAINT world_npc_definitions_npc_type_check
 CHECK (npc_type IN ('guide','trial_master','judge','soup_keeper','guard','blacksmith'));
ALTER TABLE world_npc_definitions DROP CONSTRAINT IF EXISTS world_npc_definitions_interaction_type_check;
ALTER TABLE world_npc_definitions ADD CONSTRAINT world_npc_definitions_interaction_type_check
 CHECK (interaction_type IN ('dialogue','soul_trials','soul_judgement','reincarnation_guidance','world_guard','equipment_crafting'));
INSERT INTO world_npc_definitions
 (id,world_id,name,title,npc_type,interaction_type,position_x,position_y,position_z,rotation_y,interaction_radius,dialogue)
VALUES
 ('fengdu_blacksmith','underworld_fengdu','铁砧老周','万家魂坊 · 鬼工坊','blacksmith','equipment_crafting',-55,0,-66,0,4.5,
  '{"greeting":"生魂也好，游魂也罢，想要趁手兵刃就来找老周。荒狼骨料韧性足，正适合打制初阶兵器。","topics":["打造会消耗背包中的材料，并生成带随机词缀的独立装备。","装备品质越高，可强化的等级上限越高。","不需要的装备可以分解为锻造材料。"]}'::jsonb)
ON CONFLICT(id) DO UPDATE SET
 name=EXCLUDED.name,title=EXCLUDED.title,npc_type=EXCLUDED.npc_type,
 interaction_type=EXCLUDED.interaction_type,position_x=EXCLUDED.position_x,
 position_y=EXCLUDED.position_y,position_z=EXCLUDED.position_z,
 rotation_y=EXCLUDED.rotation_y,interaction_radius=EXCLUDED.interaction_radius,
 dialogue=EXCLUDED.dialogue,enabled=TRUE,updated_at=now();
COMMIT;
