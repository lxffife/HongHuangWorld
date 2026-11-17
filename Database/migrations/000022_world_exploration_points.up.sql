BEGIN;

-- Exploration discoveries belong to the soul and survive reincarnation.
-- Coordinates and rewards are server-authored; clients submit point IDs only.
CREATE TABLE world_exploration_points (
    id VARCHAR(96) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id) ON DELETE CASCADE,
    region_id VARCHAR(96) NOT NULL,
    name VARCHAR(96) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    position_x DOUBLE PRECISION NOT NULL,
    position_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_z DOUBLE PRECISION NOT NULL,
    interaction_radius DOUBLE PRECISION NOT NULL DEFAULT 4 CHECK (interaction_radius BETWEEN 1 AND 20),
    danger_level SMALLINT NOT NULL DEFAULT 1 CHECK (danger_level BETWEEN 1 AND 10),
    merit_reward SMALLINT NOT NULL DEFAULT 0 CHECK (merit_reward BETWEEN 0 AND 5),
    karma_delta SMALLINT NOT NULL DEFAULT 0 CHECK (karma_delta BETWEEN -5 AND 5),
    required_race_id VARCHAR(64),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_world_exploration_points_world
    ON world_exploration_points(world_id, enabled, region_id);

CREATE TABLE soul_exploration_discoveries (
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    point_id VARCHAR(96) NOT NULL REFERENCES world_exploration_points(id),
    fate_event_id UUID NOT NULL DEFAULT gen_random_uuid(),
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (soul_id, point_id),
    UNIQUE (fate_event_id)
);
CREATE INDEX idx_soul_exploration_discoveries_point
    ON soul_exploration_discoveries(point_id, discovered_at DESC);

-- Points are placed around the two server-owned Qingyun birth spawns.
INSERT INTO world_exploration_points
    (id,world_id,region_id,name,description,position_x,position_y,position_z,
     interaction_radius,danger_level,merit_reward,karma_delta,required_race_id)
VALUES
    ('misty_stream_source','qingyun_human','qingyun_misty_stream','灵溪源头',
     '溪水深处有一缕清灵之气盘旋。静心感知水脉流向，可辨认灵溪的源头。',
     14,0,-10,4,1,1,0,NULL),
    ('old_stone_bridge','qingyun_human','qingyun_misty_stream','古石桥',
     '石桥基座刻着被岁月磨损的符纹。辨认纹路后，记录下这处古老遗迹。',
     8,0,-5,4,2,1,0,NULL),
    ('spirit_herb_slope','qingyun_human','qingyun_misty_stream','灵草坡',
     '坡地生长着常见灵草，观察灵植分布与灵气变化，积累初入山门的见闻。',
     17,0,-4,4,2,1,0,NULL),
    ('beast_totem_rock','qingyun_human','qingyun_beast_ridge','兽纹岩',
     '岩壁上的古老兽纹与山岭灵脉相互呼应。辨识纹路，追溯此地兽息来源。',
     -16,0,12,4,3,2,0,NULL),
    ('wind_howl_pass','qingyun_human','qingyun_beast_ridge','啸风隘口',
     '隘口风声中夹杂着妖兽气息。观察风向与兽迹，熟悉百兽岭的危险。',
     -21,0,17,4,4,2,0,NULL),
    ('ancient_tree_hollow','qingyun_human','qingyun_beast_ridge','古木空洞',
     '古木内部残留着微弱的灵性回响。探索树洞，记录其中保存的古老气息。',
     -14,0,19,4,4,2,0,NULL)
ON CONFLICT (id) DO NOTHING;

COMMIT;
