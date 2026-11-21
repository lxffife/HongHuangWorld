BEGIN;

-- Supports chunk aggregation and per-monster-life audit pagination.
CREATE INDEX idx_bounty_monster_contribution_task_instance_created
    ON bounty_monster_contribution_events(task_id, monster_instance_id, created_at);

COMMIT;
