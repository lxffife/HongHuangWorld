BEGIN;

-- Cancellation and expiry are terminal participant states distinct from failure.
ALTER TABLE bounty_task_participants
    DROP CONSTRAINT IF EXISTS bounty_task_participants_status_check;
ALTER TABLE bounty_task_participants
    ADD CONSTRAINT bounty_task_participants_status_check
    CHECK (status IN ('accepted','withdrawn','completed','failed','cancelled'));

CREATE TABLE bounty_task_refunds (
    task_id UUID PRIMARY KEY REFERENCES bounty_tasks(id) ON DELETE RESTRICT,
    event_key VARCHAR(128) NOT NULL UNIQUE,
    refunded_by UUID,
    refunded_amount BIGINT NOT NULL CHECK (refunded_amount > 0),
    reason VARCHAR(16) NOT NULL CHECK (reason IN ('cancelled','expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bounty_tasks_due_expiry
    ON bounty_tasks(expires_at,id)
    WHERE status IN ('open','in_progress','full') AND expires_at IS NOT NULL;

COMMIT;
