BEGIN;
DROP INDEX IF EXISTS idx_chat_messages_nearby_instance_history;
ALTER TABLE chat_messages DROP CONSTRAINT IF EXISTS chk_chat_nearby_instance_scope;
COMMIT;
