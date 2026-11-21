BEGIN;
DROP TRIGGER IF EXISTS bounty_monster_contributors_immutable ON bounty_monster_contributors;
DROP TRIGGER IF EXISTS bounty_monster_contribution_events_immutable ON bounty_monster_contribution_events;
DROP FUNCTION IF EXISTS prevent_bounty_monster_contribution_mutation();
DROP TABLE IF EXISTS bounty_monster_contributors;
DROP TABLE IF EXISTS bounty_monster_contribution_events;
COMMIT;
