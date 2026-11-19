BEGIN;

-- Friend requests are intentionally separate from stranger private-message requests.
ALTER TABLE chat_preferences
    ADD COLUMN allow_friend_requests BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE chat_friend_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_character_id UUID NOT NULL,
    addressee_character_id UUID NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','accepted','rejected','cancelled')),
    message VARCHAR(200) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CHECK (requester_character_id <> addressee_character_id)
);

CREATE UNIQUE INDEX uq_chat_friend_requests_pending
    ON chat_friend_requests(requester_character_id, addressee_character_id)
    WHERE status='pending';
CREATE INDEX idx_chat_friend_requests_inbox
    ON chat_friend_requests(addressee_character_id, status, created_at DESC);
CREATE INDEX idx_chat_friend_requests_outbox
    ON chat_friend_requests(requester_character_id, status, created_at DESC);

-- Store each accepted friendship once using a canonical unordered pair.
-- Collapse any legacy reverse duplicates before enforcing pair uniqueness.
DELETE FROM chat_friendships a
USING chat_friendships b
WHERE LEAST(a.requester_character_id, a.addressee_character_id) =
      LEAST(b.requester_character_id, b.addressee_character_id)
  AND GREATEST(a.requester_character_id, a.addressee_character_id) =
      GREATEST(b.requester_character_id, b.addressee_character_id)
  AND a.id > b.id;

CREATE UNIQUE INDEX uq_chat_friendships_unordered
    ON chat_friendships (
        LEAST(requester_character_id, addressee_character_id),
        GREATEST(requester_character_id, addressee_character_id)
    );

CREATE TABLE chat_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_low UUID NOT NULL,
    participant_high UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (participant_low < participant_high),
    UNIQUE (participant_low, participant_high)
);

ALTER TABLE chat_messages
    ADD COLUMN conversation_id UUID REFERENCES chat_conversations(id) ON DELETE CASCADE;

CREATE INDEX idx_chat_messages_conversation_history
    ON chat_messages(conversation_id, created_at DESC, id DESC)
    WHERE conversation_id IS NOT NULL;

COMMIT;
