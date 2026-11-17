BEGIN;
CREATE TABLE world_exploration_events (
 id VARCHAR(96) PRIMARY KEY,
 point_id VARCHAR(96) NOT NULL REFERENCES world_exploration_points(id) ON DELETE CASCADE,
 title VARCHAR(120) NOT NULL,
 description TEXT NOT NULL,
 event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('spirit_resonance','ancient_mechanism','beast_trace')),
 required_race_id VARCHAR(64),
 required_fate_trait_id VARCHAR(48) CHECK (required_fate_trait_id IS NULL OR required_fate_trait_id IN ('unmarked_fate','blessed_fate','karmic_shadow','entangled_fate')),
 merit_reward SMALLINT NOT NULL DEFAULT 0 CHECK (merit_reward BETWEEN 0 AND 5),
 karma_delta SMALLINT NOT NULL DEFAULT 0 CHECK (karma_delta BETWEEN -5 AND 5),
 enabled BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_world_exploration_events_point ON world_exploration_events(point_id, enabled);
CREATE TABLE soul_exploration_event_claims (
 soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
 event_id VARCHAR(96) NOT NULL REFERENCES world_exploration_events(id),
 fate_event_id UUID NOT NULL DEFAULT gen_random_uuid(),
 claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (soul_id,event_id),
 UNIQUE (fate_event_id)
);
CREATE INDEX idx_soul_exploration_event_claims_event ON soul_exploration_event_claims(event_id,claimed_at DESC);
INSERT INTO world_exploration_events(id,point_id,title,description,event_type,merit_reward,karma_delta) VALUES
('misty_stream_spirit_resonance','misty_stream_source','灵溪共鸣','你将神识沉入溪流，察觉水脉深处有灵气随呼吸起伏。灵溪回应了你的感知，一缕清灵之气融入灵魂。','spirit_resonance',2,0),
('old_stone_bridge_ancient_mechanism','old_stone_bridge','桥下古阵','你循着石桥基座的残缺符纹找到隐蔽阵眼。阵法虽已沉寂，残存的阵意仍为你揭示了一段古老见闻。','ancient_mechanism',2,-1),
('beast_totem_ancestral_echo','beast_totem_rock','百兽祖纹回响','指尖触及兽纹岩的一刻，沉睡的古老兽意轰然回响。你从回响中辨认出山岭的守护誓约。','beast_trace',3,1)
ON CONFLICT(id) DO NOTHING;

UPDATE world_exploration_events SET required_race_id='human' WHERE id='misty_stream_spirit_resonance';
UPDATE world_exploration_events SET required_race_id='demon' WHERE id='beast_totem_ancestral_echo';
UPDATE world_exploration_events SET required_fate_trait_id='karmic_shadow' WHERE id='old_stone_bridge_ancient_mechanism';
COMMIT;
