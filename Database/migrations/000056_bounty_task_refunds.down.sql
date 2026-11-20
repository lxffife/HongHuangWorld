BEGIN;

DROP INDEX IF EXISTS idx_bounty_tasks_due_expiry;
DROP TABLE IF EXISTS bounty_task_refunds;

-- Preserve rows created by the newer state machine when rolling back the enum extension.
UPDATE bounty_task_participants SET status = 'withdrawn' WHERE status = 'cancelled';

ALTER TABLE bounty_task_participants
    DROP CONSTRAINT IF EXISTS bounty_task_participants_status_check;
ALTER TABLE bounty_task_participants
    ADD CONSTRAINT bounty_task_participants_status_check
    CHECK (status IN ('accepted','withdrawn','completed','failed'));

COMMIT;
