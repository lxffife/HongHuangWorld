BEGIN;

-- A task may define several objective counters. WorldServer reports only one
-- verified event at a time; the center service derives all progress changes.
CREATE TABLE bounty_task_objectives (
    task_id UUID NOT NULL REFERENCES bounty_tasks(id) ON DELETE CASCADE,
    objective_key VARCHAR(64) NOT NULL,
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN (
        'monster_killed','exploration_discovered','escort_checkpoint','item_collected'
    )),
    target_count INTEGER NOT NULL CHECK (target_count BETWEEN 1 AND 100000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, objective_key)
);

CREATE TABLE bounty_task_objective_progress (
    task_id UUID NOT NULL,
    account_id UUID NOT NULL,
    objective_key VARCHAR(64) NOT NULL,
    progress_count INTEGER NOT NULL DEFAULT 0 CHECK (progress_count >= 0),
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, account_id, objective_key),
    FOREIGN KEY (task_id, account_id)
        REFERENCES bounty_task_participants(task_id, account_id) ON DELETE CASCADE,
    FOREIGN KEY (task_id, objective_key)
        REFERENCES bounty_task_objectives(task_id, objective_key) ON DELETE CASCADE
);

CREATE INDEX idx_bounty_objective_progress_account
    ON bounty_task_objective_progress(account_id, updated_at DESC);

-- event_id is globally unique. The payload is intentionally narrow: no client
-- supplied reward, delta, account ID, or completion flag is accepted.
CREATE TABLE bounty_task_events (
    event_id UUID PRIMARY KEY,
    task_id UUID NOT NULL,
    account_id UUID NOT NULL,
    character_id UUID NOT NULL REFERENCES characters(id),
    session_id UUID NOT NULL REFERENCES world_sessions(id),
    node_key VARCHAR(96) NOT NULL,
    objective_key VARCHAR(64) NOT NULL,
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN (
        'monster_killed','exploration_discovered','escort_checkpoint','item_collected'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (task_id, account_id)
        REFERENCES bounty_task_participants(task_id, account_id),
    FOREIGN KEY (task_id, objective_key)
        REFERENCES bounty_task_objectives(task_id, objective_key)
);

CREATE INDEX idx_bounty_task_events_task_created
    ON bounty_task_events(task_id, created_at DESC);
CREATE INDEX idx_bounty_task_events_account_created
    ON bounty_task_events(account_id, created_at DESC);

CREATE OR REPLACE FUNCTION prevent_bounty_task_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'bounty task events are immutable';
END;
$$;

CREATE TRIGGER bounty_task_events_immutable
BEFORE UPDATE OR DELETE ON bounty_task_events
FOR EACH ROW EXECUTE FUNCTION prevent_bounty_task_event_mutation();

COMMIT;
