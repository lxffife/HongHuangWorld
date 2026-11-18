BEGIN;

-- The outbox row is inserted in the same PostgreSQL transaction as chat_messages.
-- A publisher may safely retry after a process crash; message_id is the idempotency key.
CREATE TABLE chat_event_outbox (
    message_id UUID PRIMARY KEY REFERENCES chat_messages(id) ON DELETE CASCADE,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_until TIMESTAMPTZ,
    locked_by VARCHAR(96),
    last_error TEXT,
    CHECK ((locked_until IS NULL) = (locked_by IS NULL))
);

CREATE INDEX idx_chat_event_outbox_pending
    ON chat_event_outbox(next_attempt_at, created_at, message_id)
    WHERE published_at IS NULL;

CREATE INDEX idx_chat_event_outbox_expired_locks
    ON chat_event_outbox(locked_until)
    WHERE published_at IS NULL AND locked_until IS NOT NULL;

COMMIT;
