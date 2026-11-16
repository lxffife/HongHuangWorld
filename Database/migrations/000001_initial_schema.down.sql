BEGIN;

DROP TABLE IF EXISTS world_sessions;
DROP TABLE IF EXISTS world_entry_tickets;
ALTER TABLE IF EXISTS souls DROP CONSTRAINT IF EXISTS fk_souls_current_character;
DROP TABLE IF EXISTS characters;
ALTER TABLE IF EXISTS world_instances DROP COLUMN IF EXISTS server_id;
DROP TABLE IF EXISTS server_registry;
DROP TABLE IF EXISTS world_instances;
DROP TABLE IF EXISTS world_definitions;
DROP TABLE IF EXISTS souls;
DROP TABLE IF EXISTS account_sessions;
DROP TABLE IF EXISTS accounts;

COMMIT;
