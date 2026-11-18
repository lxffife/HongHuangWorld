BEGIN;

-- A dedicated high-risk soul body for the ancient battlefield branch.
-- It inherits the mythic war-soul reward profile but has its own causal gate.
INSERT INTO soul_absorption_kinds
    (id,name,description,base_energy,trait_key,inheritance_attribute,rarity,quality_tier,progress_units)
SELECT 'ancient_battlefield_god_soul','古战场上古战神残魂',
       '古战场遗迹中沉睡的上古战神意志，只有选择召唤战神的灵魂才能承接其魂质，提供八倍力量资质成长进度',
       base_energy,trait_key,'strength','mythic','mythic',8
FROM soul_absorption_kinds
WHERE id='blazing_war_soul_mythic'
ON CONFLICT (id) DO UPDATE SET
    name=EXCLUDED.name,
    description=EXCLUDED.description,
    base_energy=EXCLUDED.base_energy,
    trait_key=EXCLUDED.trait_key,
    inheritance_attribute=EXCLUDED.inheritance_attribute,
    rarity=EXCLUDED.rarity,
    quality_tier=EXCLUDED.quality_tier,
    progress_units=EXCLUDED.progress_units,
    enabled=TRUE;

INSERT INTO world_exploration_points
    (id,world_id,region_id,name,description,position_x,position_y,position_z,
     interaction_radius,danger_level,merit_reward,karma_delta)
VALUES
    ('fengdu_ancient_battlefield','underworld_fengdu','fengdu_ancient_battlefield',
     '古战场遗址','酆都荒原深处埋着断裂的战旗与兵刃。残存战意仍在呼唤后来者，贸然回应可能唤醒沉睡的战神。',
     -43,0,27,5,6,2,0)
ON CONFLICT (id) DO UPDATE SET
    name=EXCLUDED.name,description=EXCLUDED.description,
    position_x=EXCLUDED.position_x,position_y=EXCLUDED.position_y,position_z=EXCLUDED.position_z,
    interaction_radius=EXCLUDED.interaction_radius,danger_level=EXCLUDED.danger_level,enabled=TRUE;

INSERT INTO world_exploration_events
    (id,point_id,title,description,event_type,merit_reward,karma_delta,choices)
VALUES
    ('fengdu_ancient_battlefield','fengdu_ancient_battlefield','古战场残念',
     '断旗之下，一道披覆古甲的残影缓缓苏醒。它曾率军镇守冥界边关，如今只剩两条道路：封存战意，让残魂安息；或以自身因果为引，召回上古战神。',
     'ancient_mechanism',2,0,
     '[
       {"id":"seal_battlefield","text":"封存战意，让残魂安息","description":"你以魂光镇住遗迹，不再惊扰沉睡的英灵。","result":"断旗缓缓垂落，古战场重新归于寂静。你获得了守护英灵的认可。","effect_key":"battlefield_seal"},
       {"id":"summon_war_god","text":"以因果为引，召唤上古战神","description":"你愿承担战神苏醒后的危险，尝试唤回那道不灭战意。","result":"地底传来战鼓回响，古老战意记住了你的灵魂。上古战神残魂将可能现身，只有你能承接这份魂质。","effect_key":"battlefield_summon"}
     ]'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    point_id=EXCLUDED.point_id,title=EXCLUDED.title,description=EXCLUDED.description,
    event_type=EXCLUDED.event_type,merit_reward=EXCLUDED.merit_reward,
    karma_delta=EXCLUDED.karma_delta,choices=EXCLUDED.choices,enabled=TRUE;

COMMIT;
