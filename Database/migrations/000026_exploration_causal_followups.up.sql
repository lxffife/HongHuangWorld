BEGIN;

-- A follow-up event is unlocked only by a prior soul-owned claim and the
-- exact branch chosen for that claim. Clients never submit prerequisite state.
ALTER TABLE world_exploration_events
    ADD COLUMN required_event_id VARCHAR(96)
        REFERENCES world_exploration_events(id) ON DELETE CASCADE,
    ADD COLUMN required_choice_id VARCHAR(64),
    ADD CONSTRAINT chk_world_exploration_event_prerequisite_pair
        CHECK ((required_event_id IS NULL) = (required_choice_id IS NULL));

INSERT INTO world_exploration_points
    (id,world_id,region_id,name,description,position_x,position_y,position_z,
     interaction_radius,danger_level,merit_reward,karma_delta)
VALUES
    ('fengdu_lantern_shadow_trace','underworld_fengdu','fengdu_gate_outskirts','魂灯旧影',
     '引魂灯火被收取后，灯座深处浮现一道旧日影痕。靠近细察，可追寻灯火曾照见的前尘。',
     13,0,-14,4,2,1,0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO world_exploration_events
    (id,point_id,title,description,event_type,merit_reward,karma_delta,choices)
VALUES
    ('fengdu_lantern_old_shadow','fengdu_lantern_shadow_trace','魂灯旧影',
     '灯座深处的残影映出一位曾守在鬼门关前的引魂人。那段记忆似乎与你收取的灯火存在因果。',
     'spirit_resonance',2,0,
     '[
       {"id":"follow_lantern_shadow","text":"追随旧影，寻找引魂人的去向","description":"你循着残影留下的微光，试图追查引魂灯的来历。","result":"旧影指向酆都深处的一段古老誓约，你的灵魂记住了这条线索。","effect_key":"lantern_shadow_follow"},
       {"id":"release_lantern_shadow","text":"放归旧影，让守灯者安息","description":"你不再追问旧影的来历，选择让残存执念随灯火散去。","result":"旧影化作温和的光点消散，灯座终于恢复宁静。","effect_key":"lantern_shadow_release"}
     ]'::jsonb)
ON CONFLICT (id) DO NOTHING;

UPDATE world_exploration_events
SET required_event_id='fengdu_lantern_memory',
    required_choice_id='take_soul_flame'
WHERE id='fengdu_lantern_old_shadow';

COMMIT;
