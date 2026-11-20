BEGIN;

DROP INDEX IF EXISTS idx_bounty_tasks_due_expiry;
DROP TABLE IF EXISTS bounty_task_refunds;

ALTER TABLE bounty_task_participants
    DROP CONSTRAINT IF EXISTS bounty_task_participants_status_check;
ALTER TABLE bounty_task_participants
    ADD CONSTRAINT bounty_task_participants_status_check
    CHECK (status IN ('accepted','withdrawn','completed','failed'));

COMMIT;
