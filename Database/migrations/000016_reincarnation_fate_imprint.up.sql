BEGIN;

-- Snapshot the soul's fate at the moment a new body is created. This is an
-- immutable narrative seed for future birth routes and world/NPC reactions.
ALTER TABLE reincarnation_events
    ADD COLUMN fate_karma BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN fate_merit BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN fate_aspect VARCHAR(32) NOT NULL DEFAULT '因果未定';

ALTER TABLE reincarnation_events
    ADD CONSTRAINT chk_reincarnation_fate_aspect
    CHECK (fate_aspect IN ('因果未定', '福缘深厚', '业障缠身', '福祸交织'));

COMMIT;
