BEGIN;

CREATE TABLE game_config_revisions (
    id BIGSERIAL PRIMARY KEY,
    resource_type VARCHAR(48) NOT NULL,
    resource_id VARCHAR(160) NOT NULL,
    revision_number INTEGER NOT NULL CHECK (revision_number > 0),
    old_snapshot JSONB,
    new_snapshot JSONB,
    change_kind VARCHAR(16) NOT NULL CHECK (change_kind IN ('create','update','delete','rollback')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(resource_type, resource_id, revision_number)
);
CREATE INDEX idx_game_config_revisions_resource
    ON game_config_revisions(resource_type, resource_id, revision_number DESC);
CREATE INDEX idx_game_config_revisions_created
    ON game_config_revisions(created_at DESC);

COMMIT;
