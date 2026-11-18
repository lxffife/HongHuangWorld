BEGIN;

-- One row per live Chat WebSocket connection. This is an expiring lease,
-- not an Identity login session and not durable user history.
CREATE TABLE chat_presence_sessions (
    connection_id UUID PRIMARY KEY,
    account_id UUID NOT NULL,
    character_id UUID,
    node_id VARCHAR(96) NOT NULL,
    connected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    CHECK (expires_at > connected_at),
    CHECK (last_seen_at >= connected_at)
);

CREATE INDEX idx_chat_presence_account_active
    ON chat_presence_sessions(account_id, expires_at DESC);

CREATE INDEX idx_chat_presence_expiry
    ON chat_presence_sessions(expires_at);

COMMIT;
