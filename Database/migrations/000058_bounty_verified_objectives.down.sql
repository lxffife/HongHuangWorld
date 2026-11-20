BEGIN;
DROP TRIGGER IF EXISTS bounty_task_events_immutable ON bounty_task_events;
DROP FUNCTION IF EXISTS prevent_bounty_task_event_mutation();
DROP TABLE IF EXISTS bounty_task_events;
DROP TABLE IF EXISTS bounty_task_objective_progress;
DROP TABLE IF EXISTS bounty_task_objectives;
COMMIT;
