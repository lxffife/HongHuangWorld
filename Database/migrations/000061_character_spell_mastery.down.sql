BEGIN;
DROP INDEX IF EXISTS idx_character_spell_mastery_events_character;
DROP TABLE IF EXISTS character_spell_mastery_events;
DROP TABLE IF EXISTS character_spell_mastery;
COMMIT;
