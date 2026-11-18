BEGIN;

-- Chat owns these projections. They intentionally have no foreign keys into
-- Identity or Game databases; Game state arrives as versioned events.
CREATE TABLE chat_accounts (
    account_id UUID PRIMARY KEY,
    current_character_id UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_characters (
    character_id UUID PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    race_id VARCHAR(64) NOT NULL DEFAULT '',
    level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 0),
    world_id VARCHAR(64) NOT NULL DEFAULT '',
    status VARCHAR(24) NOT NULL DEFAULT 'alive',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_characters_world ON chat_characters(world_id, status);

CREATE TABLE chat_server_nodes (
    node_key VARCHAR(96) PRIMARY KEY,
    status VARCHAR(24) NOT NULL DEFAULT 'offline',
    last_heartbeat_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_world_instances (
    instance_id UUID PRIMARY KEY,
    world_id VARCHAR(64) NOT NULL,
    node_key VARCHAR(96) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'offline',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_world_instances_node ON chat_world_instances(node_key, status, world_id);

CREATE TABLE chat_world_sessions (
    session_id UUID PRIMARY KEY,
    character_id UUID NOT NULL,
    instance_id UUID NOT NULL,
    node_key VARCHAR(96) NOT NULL,
    session_state VARCHAR(24) NOT NULL,
    disconnected_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_world_sessions_character ON chat_world_sessions(character_id, session_state);
CREATE INDEX idx_chat_world_sessions_instance ON chat_world_sessions(instance_id, node_key, session_state);

CREATE TABLE chat_preferences (
    character_id UUID PRIMARY KEY,
    allow_stranger_requests BOOLEAN NOT NULL DEFAULT TRUE,
    allow_nearby_messages BOOLEAN NOT NULL DEFAULT TRUE,
    allow_world_messages BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_character_id UUID NOT NULL,
    addressee_character_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (requester_character_id <> addressee_character_id),
    UNIQUE (requester_character_id, addressee_character_id)
);
CREATE INDEX idx_chat_friendships_addressee ON chat_friendships(addressee_character_id);

CREATE TABLE chat_private_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_character_id UUID NOT NULL,
    addressee_character_id UUID NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','cancelled')),
    message TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CHECK (requester_character_id <> addressee_character_id)
);
CREATE UNIQUE INDEX uq_chat_private_request_pending
    ON chat_private_requests(requester_character_id, addressee_character_id)
    WHERE status='pending';
CREATE INDEX idx_chat_private_requests_inbox
    ON chat_private_requests(addressee_character_id, status, created_at DESC);

CREATE TABLE chat_blocks (
    blocker_character_id UUID NOT NULL,
    blocked_character_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (blocker_character_id <> blocked_character_id),
    PRIMARY KEY (blocker_character_id, blocked_character_id)
);

CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_type VARCHAR(24) NOT NULL CHECK (channel_type IN ('nearby','world','cross_world','party','sect','whisper','system','shout')),
    world_id VARCHAR(64),
    world_instance_id UUID,
    nearby_recipient_character_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    sender_character_id UUID NOT NULL,
    recipient_character_id UUID,
    client_message_id UUID NOT NULL,
    sender_name VARCHAR(96) NOT NULL,
    sender_race VARCHAR(64) NOT NULL DEFAULT '',
    sender_level INTEGER NOT NULL DEFAULT 1 CHECK (sender_level >= 0),
    content VARCHAR(800) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((channel_type='whisper' AND recipient_character_id IS NOT NULL) OR (channel_type<>'whisper' AND recipient_character_id IS NULL)),
    CHECK ((channel_type='world' AND world_id IS NOT NULL) OR channel_type<>'world'),
    CHECK (channel_type <> 'nearby' OR world_instance_id IS NOT NULL),
    CHECK (jsonb_typeof(nearby_recipient_character_ids) = 'array'),
    UNIQUE(sender_character_id, client_message_id)
);
CREATE INDEX idx_chat_messages_world_history
    ON chat_messages(world_id, created_at DESC, id DESC)
    WHERE channel_type='world';
CREATE INDEX idx_chat_messages_cross_world_history
    ON chat_messages(created_at DESC, id DESC)
    WHERE channel_type='cross_world';
CREATE INDEX idx_chat_messages_nearby_instance_history
    ON chat_messages(world_instance_id, created_at DESC, id DESC)
    WHERE channel_type='nearby';
CREATE INDEX idx_chat_messages_whisper_history
    ON chat_messages(sender_character_id, recipient_character_id, created_at DESC)
    WHERE channel_type='whisper';
CREATE INDEX idx_chat_messages_retention ON chat_messages(created_at);

-- Chat's own transactional outbox: message persistence and fanout intent commit
-- atomically inside this database.
CREATE TABLE chat_event_outbox (
    message_id UUID PRIMARY KEY,
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

-- Idempotent inbox for Game -> Chat projection events.
CREATE TABLE game_projection_inbox (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(96) NOT NULL,
    aggregate_id VARCHAR(96) NOT NULL,
    payload JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);
CREATE INDEX idx_game_projection_inbox_pending
    ON game_projection_inbox(received_at, event_id)
    WHERE processed_at IS NULL;

COMMIT;
