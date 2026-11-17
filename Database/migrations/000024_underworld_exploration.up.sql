BEGIN;

-- First exploration layer for the Underworld. Discovery and rewards remain
-- soul-owned and are validated by the center server against saved position.
INSERT INTO world_exploration_points
    (id,world_id,region_id,name,description,position_x,position_y,position_z,
     interaction_radius,danger_level,merit_reward,karma_delta)
VALUES
    ('fengdu_gate_soul_lantern','underworld_fengdu','fengdu_gate_outskirts','引魂灯',
     '鬼门关外的魂灯映照着新魂来路。靠近灯火，辨认其中残存的引魂符印。',
     7,0,-14,4,1,1,0),
    ('forgotten_river_echo_stone','underworld_fengdu','wangchuan_riverside','忘川回音石',
     '河岸回音石收纳着无主的低语。静听片刻，辨认一段未散的前尘。',
     22,0,-18,4,2,1,0),
    ('naihe_bridge_soul_mark','underworld_fengdu','naihe_bridge','奈何桥魂印',
     '桥栏石刻留有历代过桥魂魄的微弱印记。触摸石刻，可记录一缕轮回痕迹。',
     22,0,2,4,2,2,0),
    ('reincarnation_hall_tablet','underworld_fengdu','reincarnation_hall_front','轮回殿旧碑',
     '轮回殿前的旧碑记载着肉身与灵魂分离的古老规矩。仔细辨读，理解轮回秩序。',
     0,0,12,4,3,2,0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO world_exploration_events
    (id,point_id,title,description,event_type,merit_reward,karma_delta)
VALUES
    ('fengdu_lantern_memory','fengdu_gate_soul_lantern','魂灯认主',
     '魂灯中的微光与你的灵魂短暂共鸣。你感知到此世肉身虽会消亡，灵魂却能承载因果。',
     'spirit_resonance',2,0),
    ('wangchuan_past_echo','forgotten_river_echo_stone','忘川前尘',
     '回音石映出一段模糊前尘。你没有追逐幻象，而是将这段记忆化作继续前行的力量。',
     'spirit_resonance',2,1),
    ('naihe_bridge_ancient_oath','naihe_bridge_soul_mark','奈何旧誓',
     '桥栏上的古老誓纹回应了你的触碰。你从中读出一条被遗忘的引渡誓约。',
     'ancient_mechanism',2,-1),
    ('reincarnation_hall_cycle','reincarnation_hall_tablet','轮回碑文',
     '碑文揭示了灵魂、肉身与轮回之间的关系。你对冥界秩序有了更深理解。',
     'ancient_mechanism',3,0)
ON CONFLICT (id) DO NOTHING;

COMMIT;
