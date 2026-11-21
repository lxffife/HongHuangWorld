BEGIN;

-- Immutable audit snapshots for authoritative per-monster damage contributions.
-- This table deliberately does not alter bounty objective counters or payouts.
CREATE TABLE bounty_monster_contribution_events (
    event_id UUID PRIMARY KEY,
    task_id UUID NOT NULL REFERENCES bounty_tasks(id),
    node_key VARCHAR(96) NOT NULL,
    monster_instance_id VARCHAR(96) NOT NULL,
    monster_definition_id VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (task_id, monster_definition_id)
        REFERENCES bounty_task_objectives(task_id, objective_key)
);

CREATE INDEX idx_bounty_monster_contribution_task_created
    ON bounty_monster_contribution_events(task_id, created_at DESC);

CREATE TABLE bounty_monster_contributors (
    event_id UUID NOT NULL REFERENCES bounty_monster_contribution_events(event_id),
    session_id UUID NOT NULL REFERENCES world_sessions(id),
    character_id UUID NOT NULL REFERENCES characters(id),
    account_id UUID NOT NULL,
    damage BIGINT NOT NULL CHECK (damage > 0),
    hit_count BIGINT NOT NULL CHECK (hit_count > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, session_id, character_id)
);

CREATE INDEX idx_bounty_monster_contributors_account
    ON bounty_monster_contributors(account_id, created_at DESC);

CREATE OR REPLACE FUNCTION prevent_bounty_monster_contribution_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'bounty monster contribution records are immutable';
END;
$$;

CREATE TRIGGER bounty_monster_contribution_events_immutable
BEFORE UPDATE OR DELETE ON bounty_monster_contribution_events
FOR EACH ROW EXECUTE FUNCTION prevent_bounty_monster_contribution_mutation();

CREATE TRIGGER bounty_monster_contributors_immutable
BEFORE UPDATE OR DELETE ON bounty_monster_contributors
FOR EACH ROW EXECUTE FUNCTION prevent_bounty_monster_contribution_mutation();

COMMIT;
