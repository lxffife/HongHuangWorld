BEGIN;

-- NPCs are world data, not client-authored scene objects. Coordinates are
-- authoritative world-space X/Z values used by the interaction distance check.
CREATE TABLE world_npc_definitions (
    id VARCHAR(64) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id) ON DELETE CASCADE,
    name VARCHAR(96) NOT NULL,
    title VARCHAR(96) NOT NULL DEFAULT '',
    npc_type VARCHAR(32) NOT NULL CHECK (npc_type IN ('guide','trial_master','judge','soup_keeper','guard')),
    interaction_type VARCHAR(40) NOT NULL CHECK (interaction_type IN ('dialogue','soul_trials','soul_judgement','reincarnation_guidance','world_guard')),
    position_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    rotation_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    interaction_radius DOUBLE PRECISION NOT NULL DEFAULT 3.0 CHECK (interaction_radius > 0 AND interaction_radius <= 20),
    dialogue JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_world_npc_world_enabled ON world_npc_definitions(world_id, enabled);

INSERT INTO world_npc_definitions
    (id,world_id,name,title,npc_type,interaction_type,position_x,position_y,position_z,rotation_y,interaction_radius,dialogue)
VALUES
    ('fengdu_soul_guide','underworld_fengdu','引魂使','接引新魂','guide','dialogue',4,0,2,3.14,3.5,
     '{"greeting":"新来的魂魄，先熟悉酆都，再去完成引魂试炼。","topics":["冥界是每一世肉身终结后的归处。","灵魂经验跨越轮回保留，但境界需要你亲自突破。"]}'::jsonb),
    ('fengdu_trial_master','underworld_fengdu','镇祟校尉','引魂试炼','trial_master','soul_trials',8,0,1,3.14,4.0,
     '{"greeting":"游祟扰乱酆都秩序，击败它们以凝聚魂力。","trial_id":"fengdu_first_exorcism"}'::jsonb),
    ('fengdu_judge','underworld_fengdu','冥府判官','因果审录','judge','soul_judgement',-5,0,3,0,3.5,
     '{"greeting":"功德与业力皆有记录。初入冥界，先完成基础试炼。","records":["merit","karma"]}'::jsonb),
    ('fengdu_mengpo','underworld_fengdu','孟婆','忘川引渡','soup_keeper','dialogue',-9,0,-2,1.57,3.5,
     '{"greeting":"前尘不必强求尽忘，灵魂留下的印记会伴你走过轮回。","topics":["普通复活不会创建新的一世。","主动轮回将开启新的肉身人生。"]}'::jsonb),
    ('fengdu_reincarnation_guard','underworld_fengdu','轮回殿守卫','轮回殿','guard','reincarnation_guidance',0,0,12,3.14,4.0,
     '{"greeting":"轮回殿尚未对所有魂魄开放。达到聚灵境并完成冥界试炼，方可申请投胎。","required_soul_realm_order":3,"required_trial_id":"fengdu_first_exorcism"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

COMMIT;
