BEGIN;
UPDATE character_attributes ca
SET health = b.health, max_health = b.max_health,
    mana = b.mana, max_mana = b.max_mana,
    attack = b.attack, defense = b.defense, updated_at = now()
FROM character_combat_test_balance_backup b
WHERE b.character_id = ca.character_id;
DROP TABLE character_combat_test_balance_backup;

UPDATE monster_definitions
SET max_health = CASE id
        WHEN 'wilderness_wolf' THEN 80 WHEN 'wandering_wraith' THEN 80
        WHEN 'blazing_war_soul' THEN 105 WHEN 'blazing_war_soul_elite' THEN 190
        WHEN 'blazing_war_soul_ancient' THEN 360 WHEN 'ancient_battlefield_god_soul' THEN 720
        WHEN 'ironbone_beast_soul' THEN 145 WHEN 'gale_wraith' THEN 75
        WHEN 'spirit_scholar_wisp' THEN 90 WHEN 'wangchuan_echo_wisp' THEN 245
        WHEN 'life_ancient_soul' THEN 180 WHEN 'faceless_essence' THEN 220
        ELSE max_health END,
    attack = CASE id
        WHEN 'wilderness_wolf' THEN 12 WHEN 'wandering_wraith' THEN 12
        WHEN 'blazing_war_soul' THEN 16 WHEN 'blazing_war_soul_elite' THEN 22
        WHEN 'blazing_war_soul_ancient' THEN 30 WHEN 'ancient_battlefield_god_soul' THEN 38
        WHEN 'ironbone_beast_soul' THEN 13 WHEN 'gale_wraith' THEN 15
        WHEN 'spirit_scholar_wisp' THEN 18 WHEN 'wangchuan_echo_wisp' THEN 24
        WHEN 'life_ancient_soul' THEN 18 WHEN 'faceless_essence' THEN 22
        ELSE attack END,
    defense = CASE id
        WHEN 'wilderness_wolf' THEN 4 WHEN 'wandering_wraith' THEN 4
        WHEN 'blazing_war_soul' THEN 5 WHEN 'blazing_war_soul_elite' THEN 8
        WHEN 'blazing_war_soul_ancient' THEN 14 WHEN 'ancient_battlefield_god_soul' THEN 20
        WHEN 'ironbone_beast_soul' THEN 9 WHEN 'gale_wraith' THEN 3
        WHEN 'spirit_scholar_wisp' THEN 4 WHEN 'wangchuan_echo_wisp' THEN 12
        WHEN 'life_ancient_soul' THEN 10 WHEN 'faceless_essence' THEN 12
        ELSE defense END,
    updated_at = now()
WHERE id IN (
    'wilderness_wolf', 'wandering_wraith', 'blazing_war_soul',
    'blazing_war_soul_elite', 'blazing_war_soul_ancient',
    'ancient_battlefield_god_soul', 'ironbone_beast_soul', 'gale_wraith',
    'spirit_scholar_wisp', 'wangchuan_echo_wisp', 'life_ancient_soul', 'faceless_essence'
);

DELETE FROM world_monster_spawn_points WHERE id IN (
    'fengdu-gate-wraith-01', 'fengdu-gate-ironbone-01', 'fengdu-gate-elite-01',
    'wangchuan-gale-01', 'wangchuan-scholar-01', 'wangchuan-echo-elite-01',
    'battlefield-war-soul-01', 'battlefield-life-soul-01', 'battlefield-god-soul-01',
    'ghost-market-wraith-01', 'ghost-market-faceless-01'
);
COMMIT;
