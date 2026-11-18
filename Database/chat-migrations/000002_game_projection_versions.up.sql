BEGIN;

CREATE TABLE game_projection_versions (
    aggregate_id VARCHAR(96) PRIMARY KEY,
    aggregate_version BIGINT NOT NULL DEFAULT 0 CHECK (aggregate_version >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_game_projection_inbox_processed
    ON game_projection_inbox(processed_at, received_at)
    WHERE processed_at IS NULL;

COMMIT;
