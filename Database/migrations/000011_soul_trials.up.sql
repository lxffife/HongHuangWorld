BEGIN;

CREATE TABLE soul_trial_definitions (
    id VARCHAR(64) PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    name VARCHAR(96) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    objective_type VARCHAR(32) NOT NULL CHECK (objective_type IN ('monster_kill')),
    target_count INTEGER NOT NULL CHECK (target_count > 0),
    reward_experience BIGINT NOT NULL CHECK (reward_experience > 0),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO soul_trial_definitions
    (id,world_id,name,description,objective_type,target_count,reward_experience)
VALUES
    ('fengdu_first_exorcism','underworld_fengdu','引魂试炼·初除游祟',
     '在冥界击败二十只游荡妖物，凝聚魂力，证明你已能在冥界立足。',
     'monster_kill',20,100)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE soul_trial_progress (
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    trial_id VARCHAR(64) NOT NULL REFERENCES soul_trial_definitions(id),
    progress_count INTEGER NOT NULL DEFAULT 0 CHECK (progress_count >= 0),
    completed_at TIMESTAMPTZ,
    reward_granted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (soul_id,trial_id),
    CHECK (reward_granted_at IS NULL OR completed_at IS NOT NULL)
);

COMMIT;
