BEGIN;
CREATE TABLE character_combat_test_balance_backup (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    health INTEGER NOT NULL, max_health INTEGER NOT NULL,
    mana INTEGER NOT NULL, max_mana INTEGER NOT NULL,
    attack INTEGER NOT NULL, defense INTEGER NOT NULL
);
INSERT INTO character_combat_test_balance_backup
    (character_id, health, max_health, mana, max_mana, attack, defense)
SELECT ca.character_id, ca.health, ca.max_health, ca.mana, ca.max_mana, ca.attack, ca.defense
FROM character_attributes ca
JOIN characters c ON c.id = ca.character_id
WHERE c.world_id = 'underworld_fengdu'
ON CONFLICT (character_id) DO NOTHING;

-- Development test characters in Fengdu: durable health/mana and stronger attacks.
UPDATE character_attributes ca
SET max_health = GREATEST(ca.max_health, 1200),
    health = GREATEST(ca.max_health, 1200),
    max_mana = GREATEST(ca.max_mana, 600),
    mana = GREATEST(ca.max_mana, 600),
    attack = GREATEST(ca.attack, 50),
    defense = GREATEST(ca.defense, 25),
    updated_at = now()
FROM characters c
WHERE c.id = ca.character_id AND c.world_id = 'underworld_fengdu';

-- Lower ordinary/elite monster durability and attack while retaining tier gaps.
UPDATE monster_definitions
SET max_health = CASE id
        WHEN 'wilderness_wolf' THEN 45 WHEN 'wandering_wraith' THEN 45
        WHEN 'blazing_war_soul' THEN 60 WHEN 'blazing_war_soul_elite' THEN 110
        WHEN 'blazing_war_soul_ancient' THEN 190 WHEN 'ancient_battlefield_god_soul' THEN 320
        WHEN 'ironbone_beast_soul' THEN 70 WHEN 'gale_wraith' THEN 42
        WHEN 'spirit_scholar_wisp' THEN 48 WHEN 'wangchuan_echo_wisp' THEN 130
        WHEN 'life_ancient_soul' THEN 95 WHEN 'faceless_essence' THEN 120
        ELSE max_health END,
    attack = CASE id
        WHEN 'wilderness_wolf' THEN 6 WHEN 'wandering_wraith' THEN 6
        WHEN 'blazing_war_soul' THEN 8 WHEN 'blazing_war_soul_elite' THEN 11
        WHEN 'blazing_war_soul_ancient' THEN 15 WHEN 'ancient_battlefield_god_soul' THEN 18
        WHEN 'ironbone_beast_soul' THEN 7 WHEN 'gale_wraith' THEN 7
        WHEN 'spirit_scholar_wisp' THEN 8 WHEN 'wangchuan_echo_wisp' THEN 12
        WHEN 'life_ancient_soul' THEN 9 WHEN 'faceless_essence' THEN 10
        ELSE attack END,
    defense = CASE id
        WHEN 'wilderness_wolf' THEN 2 WHEN 'wandering_wraith' THEN 2
        WHEN 'blazing_war_soul' THEN 3 WHEN 'blazing_war_soul_elite' THEN 5
        WHEN 'blazing_war_soul_ancient' THEN 8 WHEN 'ancient_battlefield_god_soul' THEN 12
        WHEN 'ironbone_beast_soul' THEN 5 WHEN 'gale_wraith' THEN 2
        WHEN 'spirit_scholar_wisp' THEN 2 WHEN 'wangchuan_echo_wisp' THEN 6
        WHEN 'life_ancient_soul' THEN 5 WHEN 'faceless_essence' THEN 6
        ELSE defense END,
    updated_at = now()
WHERE id IN (
    'wilderness_wolf', 'wandering_wraith', 'blazing_war_soul',
    'blazing_war_soul_elite', 'blazing_war_soul_ancient',
    'ancient_battlefield_god_soul', 'ironbone_beast_soul', 'gale_wraith',
    'spirit_scholar_wisp', 'wangchuan_echo_wisp', 'life_ancient_soul', 'faceless_essence'
);

-- Four hunting grounds. Each mixes easy prey, a mid-tier monster and a rare elite.
INSERT INTO world_monster_spawn_points
    (id, world_id, monster_id, spawn_x, spawn_z, rare_spawn,
     spawn_chance_percent, retry_spawn_seconds, first_spawn_delay_seconds)
VALUES
    ('fengdu-gate-wraith-01', 'underworld_fengdu', 'wandering_wraith', -7, -26, FALSE, 100, 60, 0),
    ('fengdu-gate-ironbone-01', 'underworld_fengdu', 'ironbone_beast_soul', 7, -27, FALSE, 100, 75, 0),
    ('fengdu-gate-elite-01', 'underworld_fengdu', 'blazing_war_soul_elite', 0, -36, TRUE, 12, 180, 90),
    ('wangchuan-gale-01', 'underworld_fengdu', 'gale_wraith', 19, 11, FALSE, 100, 60, 0),
    ('wangchuan-scholar-01', 'underworld_fengdu', 'spirit_scholar_wisp', 29, 22, FALSE, 100, 75, 0),
    ('wangchuan-echo-elite-01', 'underworld_fengdu', 'wangchuan_echo_wisp', 23, 42, TRUE, 10, 300, 120),
    ('battlefield-war-soul-01', 'underworld_fengdu', 'blazing_war_soul', -52, 17, FALSE, 100, 60, 0),
    ('battlefield-life-soul-01', 'underworld_fengdu', 'life_ancient_soul', -65, 31, FALSE, 100, 90, 0),
    ('battlefield-god-soul-01', 'underworld_fengdu', 'ancient_battlefield_god_soul', -88, 38, TRUE, 5, 600, 180),
    ('ghost-market-wraith-01', 'underworld_fengdu', 'wandering_wraith', 16, -40, FALSE, 100, 60, 0),
    ('ghost-market-faceless-01', 'underworld_fengdu', 'faceless_essence', 31, -40, TRUE, 8, 300, 120)
ON CONFLICT (id) DO UPDATE SET
    monster_id = EXCLUDED.monster_id, spawn_x = EXCLUDED.spawn_x, spawn_z = EXCLUDED.spawn_z,
    rare_spawn = EXCLUDED.rare_spawn, spawn_chance_percent = EXCLUDED.spawn_chance_percent,
    retry_spawn_seconds = EXCLUDED.retry_spawn_seconds,
    first_spawn_delay_seconds = EXCLUDED.first_spawn_delay_seconds,
    enabled = TRUE, updated_at = now();
COMMIT;
