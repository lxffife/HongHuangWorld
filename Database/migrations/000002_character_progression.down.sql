BEGIN;

ALTER TABLE characters DROP CONSTRAINT IF EXISTS fk_characters_race_definition;
ALTER TABLE characters ALTER COLUMN race_id DROP NOT NULL;

DROP TABLE IF EXISTS character_reward_events;
DROP TABLE IF EXISTS character_progression;
DROP TABLE IF EXISTS character_attributes;
DROP TABLE IF EXISTS realm_power_mappings;
DROP TABLE IF EXISTS cultivation_stages;
DROP TABLE IF EXISTS cultivation_realms;
DROP TABLE IF EXISTS power_tiers;
DROP TABLE IF EXISTS race_cultivation_systems;
DROP TABLE IF EXISTS cultivation_systems;
DROP TABLE IF EXISTS race_definitions;

COMMIT;
