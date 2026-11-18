BEGIN;

-- Nearby chat is scoped to one authoritative world instance. The WorldServer
-- computes its AOI recipient set; ChatServer validates that every recipient
-- still has an active session on the same instance before publishing.
ALTER TABLE chat_messages
    ADD CONSTRAINT chk_chat_nearby_instance_scope
    CHECK (channel_type <> 'nearby' OR world_instance_id IS NOT NULL);

CREATE INDEX idx_chat_messages_nearby_instance_history
    ON chat_messages(world_instance_id, created_at DESC, id DESC)
    WHERE channel_type='nearby';

COMMIT;
