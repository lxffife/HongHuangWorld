BEGIN;

ALTER TABLE reincarnation_events
    DROP CONSTRAINT IF EXISTS chk_reincarnation_fate_aspect,
    DROP COLUMN IF EXISTS fate_aspect,
    DROP COLUMN IF EXISTS fate_merit,
    DROP COLUMN IF EXISTS fate_karma;

COMMIT;
