BEGIN;

CREATE TABLE monster_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    level INTEGER NOT NULL CHECK (level BETWEEN 1 AND 10000),
    max_health DOUBLE PRECISION NOT NULL CHECK (max_health > 0 AND max_health <= 1000000000),
    attack DOUBLE PRECISION NOT NULL CHECK (attack >= 0 AND attack <= 1000000000),
    defense DOUBLE PRECISION NOT NULL CHECK (defense >= 0 AND defense <= 1000000000),
    move_speed DOUBLE PRECISION NOT NULL CHECK (move_speed > 0 AND move_speed <= 10000),
    aggro_radius DOUBLE PRECISION NOT NULL CHECK (aggro_radius > 0 AND aggro_radius <= 100000),
    leash_radius DOUBLE PRECISION NOT NULL CHECK (leash_radius >= aggro_radius AND leash_radius <= 100000),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE world_monster_spawn_points (
    id VARCHAR(96) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id) ON DELETE CASCADE,
    monster_id VARCHAR(64) NOT NULL REFERENCES monster_definitions(id),
    spawn_x DOUBLE PRECISION NOT NULL,
    spawn_z DOUBLE PRECISION NOT NULL,
    rare_spawn BOOLEAN NOT NULL DEFAULT FALSE,
    spawn_chance_percent INTEGER NOT NULL DEFAULT 100 CHECK (spawn_chance_percent BETWEEN 1 AND 100),
    retry_spawn_seconds INTEGER NOT NULL DEFAULT 60 CHECK (retry_spawn_seconds BETWEEN 1 AND 604800),
    first_spawn_delay_seconds INTEGER NOT NULL DEFAULT 0 CHECK (first_spawn_delay_seconds BETWEEN 0 AND 604800),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(world_id,id)
);
CREATE INDEX idx_world_monster_spawn_points_world_enabled
    ON world_monster_spawn_points(world_id,enabled);
CREATE INDEX idx_world_monster_spawn_points_monster
    ON world_monster_spawn_points(monster_id);

INSERT INTO monster_definitions
(id,name,level,max_health,attack,defense,move_speed,aggro_radius,leash_radius)
VALUES
('wilderness_wolf','荒原狼',3,80,12,4,2.8,10,24),
('wandering_wraith','游祟',3,80,12,4,2.4,10,24),
('blazing_war_soul','炽战残魂',4,105,16,5,2.5,11,26),
('blazing_war_soul_elite','精英炽战残魂',6,190,22,8,2.2,12,28),
('blazing_war_soul_ancient','远古炽战残魂',9,360,30,14,1.9,13,30),
('ancient_battlefield_god_soul','古战场·上古战神残魂',12,720,38,20,1.7,15,32),
('ironbone_beast_soul','铁骨兽魂',4,145,13,9,1.8,10,25),
('gale_wraith','疾风游魂',4,75,15,3,3.8,13,28),
('spirit_scholar_wisp','灵识游魂',5,90,18,4,2.2,12,27),
('wangchuan_echo_wisp','忘川回音灵识',8,245,24,12,1.8,11,26),
('life_ancient_soul','生机古魂',6,180,18,10,1.6,10,25),
('faceless_essence','无相灵魄',8,220,22,12,1.4,9,24)
ON CONFLICT(id) DO NOTHING;

INSERT INTO world_monster_spawn_points
(id,world_id,monster_id,spawn_x,spawn_z,rare_spawn,spawn_chance_percent,retry_spawn_seconds,first_spawn_delay_seconds)
VALUES
('wolf-001','qingyun_human','wilderness_wolf',-12,-8,FALSE,100,60,0),
('wolf-002','qingyun_human','wilderness_wolf',13,-7,FALSE,100,60,0),
('wolf-003','qingyun_human','wilderness_wolf',0,17,FALSE,100,60,0),
('wraith-001','underworld_fengdu','wandering_wraith',-12,-8,FALSE,100,60,0),
('wraith-002','underworld_fengdu','wandering_wraith',13,-7,FALSE,100,60,0),
('wraith-003','underworld_fengdu','wandering_wraith',0,17,FALSE,100,60,0),
('war-soul-001','underworld_fengdu','blazing_war_soul',-24,-18,FALSE,100,60,0),
('war-soul-elite-001','underworld_fengdu','blazing_war_soul_elite',-34,2,TRUE,35,180,60),
('war-soul-ancient-001','underworld_fengdu','blazing_war_soul_ancient',34,3,TRUE,12,600,240),
('battlefield-god-soul-001','underworld_fengdu','ancient_battlefield_god_soul',-43,27,TRUE,5,900,300),
('ironbone-001','underworld_fengdu','ironbone_beast_soul',25,-19,FALSE,100,60,0),
('gale-wraith-001','underworld_fengdu','gale_wraith',-26,19,FALSE,100,60,0),
('spirit-wisp-001','underworld_fengdu','spirit_scholar_wisp',26,18,FALSE,100,60,0),
('wangchuan-echo-wisp-001','underworld_fengdu','wangchuan_echo_wisp',23,-20,TRUE,20,300,90),
('life-soul-001','underworld_fengdu','life_ancient_soul',0,-30,FALSE,100,60,0),
('faceless-001','underworld_fengdu','faceless_essence',0,31,FALSE,100,60,0)
ON CONFLICT(id) DO NOTHING;

COMMIT;
