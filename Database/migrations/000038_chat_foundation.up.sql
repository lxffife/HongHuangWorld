BEGIN;

CREATE TABLE chat_preferences (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    allow_stranger_requests BOOLEAN NOT NULL DEFAULT TRUE,
    allow_nearby_messages BOOLEAN NOT NULL DEFAULT TRUE,
    allow_world_messages BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    addressee_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (requester_character_id <> addressee_character_id),
    UNIQUE (requester_character_id, addressee_character_id)
);
CREATE INDEX idx_chat_friendships_addressee ON chat_friendships(addressee_character_id);

CREATE TABLE chat_private_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    addressee_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
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
    blocker_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    blocked_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (blocker_character_id <> blocked_character_id),
    PRIMARY KEY (blocker_character_id, blocked_character_id)
);

CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_type VARCHAR(24) NOT NULL CHECK (channel_type IN ('nearby','world','cross_world','party','sect','whisper','system','shout')),
    world_id VARCHAR(64) REFERENCES world_definitions(id),
    world_instance_id UUID REFERENCES world_instances(id),
    sender_character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    recipient_character_id UUID REFERENCES characters(id) ON DELETE CASCADE,
    client_message_id UUID NOT NULL,
    content VARCHAR(800) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((channel_type='whisper' AND recipient_character_id IS NOT NULL) OR (channel_type<>'whisper' AND recipient_character_id IS NULL)),
    CHECK ((channel_type='world' AND world_id IS NOT NULL) OR channel_type<>'world'),
    UNIQUE(sender_character_id, client_message_id)
);
CREATE INDEX idx_chat_messages_world_history
    ON chat_messages(world_id, created_at DESC, id DESC)
    WHERE channel_type='world';
CREATE INDEX idx_chat_messages_cross_world_history
    ON chat_messages(created_at DESC, id DESC)
    WHERE channel_type='cross_world';
CREATE INDEX idx_chat_messages_whisper_history
    ON chat_messages(sender_character_id, recipient_character_id, created_at DESC)
    WHERE channel_type='whisper';

COMMIT;
