BEGIN;

-- Awakening is data-driven. The client requests the next stage only; the
-- server loads the threshold, checks realm/cultivation, and consumes resources.
CREATE TABLE bloodline_awakening_rules (
    target_stage SMALLINT PRIMARY KEY CHECK (target_stage BETWEEN 1 AND 9),
    min_realm_order SMALLINT NOT NULL CHECK (min_realm_order > 0),
    cultivation_cost BIGINT NOT NULL CHECK (cultivation_cost > 0),
    purity_gain INTEGER NOT NULL CHECK (purity_gain > 0 AND purity_gain <= 10000)
);

INSERT INTO bloodline_awakening_rules
    (target_stage, min_realm_order, cultivation_cost, purity_gain)
VALUES
    (1, 1, 500, 500),
    (2, 1, 1500, 500),
    (3, 1, 3000, 750),
    (4, 2, 6000, 750),
    (5, 2, 10000, 1000),
    (6, 2, 15000, 1000),
    (7, 3, 25000, 1250),
    (8, 3, 40000, 1250),
    (9, 3, 60000, 1500)
ON CONFLICT (target_stage) DO NOTHING;

-- Each new character starts with one race-native entry technique. Further
-- techniques must be granted by trusted server-side quest/drop systems.
ALTER TABLE character_techniques ADD COLUMN is_starter BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE race_starter_techniques (
    race_id VARCHAR(64) PRIMARY KEY REFERENCES race_definitions(id),
    technique_id VARCHAR(96) NOT NULL REFERENCES cultivation_techniques(id)
);

INSERT INTO race_starter_techniques (race_id, technique_id)
VALUES
    ('human', 'human_basic_qi'),
    ('demon', 'demon_breath'),
    ('witch', 'witch_blood_temper'),
    ('dragon', 'dragon_breath')
ON CONFLICT (race_id) DO NOTHING;

INSERT INTO character_techniques (character_id, technique_id, proficiency, is_equipped, is_starter)
SELECT character.id, starter.technique_id, 0, TRUE, TRUE
FROM characters character
JOIN race_starter_techniques starter ON starter.race_id = character.race_id
ON CONFLICT (character_id, technique_id) DO NOTHING;

COMMIT;
