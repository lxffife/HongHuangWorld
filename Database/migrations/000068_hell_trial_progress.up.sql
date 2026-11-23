BEGIN;

-- Per-character, server-owned progression through the eighteen underworld trials.
-- Rows are created only when a floor becomes available; clients never create progress.
CREATE TABLE character_hell_trial_progress (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    floor_number SMALLINT NOT NULL CHECK (floor_number BETWEEN 1 AND 18),
    status VARCHAR(16) NOT NULL DEFAULT 'unlocked'
        CHECK (status IN ('unlocked', 'completed')),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    first_entered_at TIMESTAMPTZ,
    last_entered_at TIMESTAMPTZ,
    entry_count INTEGER NOT NULL DEFAULT 0 CHECK (entry_count >= 0),
    completed_at TIMESTAMPTZ,
    completion_event_id UUID,
    objective_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, floor_number),
    UNIQUE (character_id, completion_event_id),
    CHECK (
        (status = 'unlocked' AND completed_at IS NULL AND completion_event_id IS NULL)
        OR
        (status = 'completed' AND completed_at IS NOT NULL AND completion_event_id IS NOT NULL)
    ),
    CHECK (last_entered_at IS NULL OR first_entered_at IS NOT NULL),
    CHECK (entry_count > 0 OR first_entered_at IS NULL)
);

CREATE INDEX idx_character_hell_trial_status
    ON character_hell_trial_progress(character_id, status, floor_number);

-- Existing characters already in the Underworld start at the first trial.
INSERT INTO character_hell_trial_progress(character_id, floor_number, status)
SELECT id, 1, 'unlocked'
FROM characters
WHERE world_id = 'underworld_fengdu'
ON CONFLICT (character_id, floor_number) DO NOTHING;

COMMIT;
