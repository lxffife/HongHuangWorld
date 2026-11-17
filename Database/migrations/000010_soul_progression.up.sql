BEGIN;

-- Permanent soul growth is independent of every physical body's race-specific cultivation.
CREATE TABLE soul_realm_definitions (
 id VARCHAR(48) PRIMARY KEY,
 name VARCHAR(48) NOT NULL,
 realm_order SMALLINT NOT NULL UNIQUE CHECK (realm_order > 0),
 required_experience BIGINT NOT NULL UNIQUE CHECK (required_experience >= 0),
 description TEXT NOT NULL DEFAULT ''
);
INSERT INTO soul_realm_definitions (id,name,realm_order,required_experience,description) VALUES
('wandering_soul','游魂境',1,0,'魂魄初聚，初入冥界'),
('condensed_soul','凝魂境',2,100,'魂体逐渐凝实，可以承受冥界基础试炼'),
('spirit_gathering','聚灵境',3,500,'能够汇聚天地灵息，取得首次投胎的基础资格'),
('spirit_body','灵体境',4,2500,'灵魂稳定，可承载更强肉身与更多种族选择'),
('soul_general','魂将境',5,10000,'魂力凝练，能够稳固保存部分前世记忆'),
('soul_king','魂王境',6,50000,'灵魂强大，可触及高阶世界的轮回门槛'),
('soul_venerable','魂尊境',7,250000,'掌握更深层的轮回印记与因果力量'),
('soul_saint','魂圣境',8,1000000,'魂道大成，具备冲击特殊轮回路线的资格')
ON CONFLICT (id) DO NOTHING;
CREATE TABLE soul_progression (
 soul_id UUID PRIMARY KEY REFERENCES souls(id) ON DELETE CASCADE,
 experience BIGINT NOT NULL DEFAULT 0 CHECK (experience >= 0),
 realm_id VARCHAR(48) NOT NULL DEFAULT 'wandering_soul' REFERENCES soul_realm_definitions(id),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO soul_progression (soul_id,experience,realm_id)
SELECT id,0,'wandering_soul' FROM souls ON CONFLICT (soul_id) DO NOTHING;
CREATE TABLE soul_reward_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
 event_id UUID NOT NULL,
 experience BIGINT NOT NULL CHECK (experience > 0 AND experience <= 1000000),
 source VARCHAR(48) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE (soul_id,event_id)
);
CREATE INDEX idx_soul_reward_events_soul ON soul_reward_events(soul_id,created_at DESC);
COMMIT;
