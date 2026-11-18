BEGIN;
INSERT INTO equipment_sets (id,name,description,bonus_tiers)
VALUES (
    'qingyun_starter_set',
    '青云初修套装',
    '由青云界初学修士常用的六件基础装备组成。集齐两件、四件与六件可逐步激活套装效果。',
    '{"2":{"attack":2},"4":{"defense":3},"6":{"defense":2,"max_health":20}}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    name=EXCLUDED.name,
    description=EXCLUDED.description,
    bonus_tiers=EXCLUDED.bonus_tiers,
    enabled=TRUE;

UPDATE item_definitions
SET equipment_set_id='qingyun_starter_set'
WHERE id IN (
    'starter_iron_sword',
    'starter_cloth_cap',
    'starter_leather_vest',
    'starter_trousers',
    'starter_travel_boots',
    'starter_wooden_charm'
);

COMMIT;
