BEGIN;
DELETE FROM character_techniques WHERE is_starter = TRUE;
DROP TABLE IF EXISTS race_starter_techniques;
ALTER TABLE character_techniques DROP COLUMN is_starter;
DROP TABLE IF EXISTS bloodline_awakening_rules;
COMMIT;
