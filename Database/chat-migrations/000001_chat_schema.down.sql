BEGIN;

DROP TABLE IF EXISTS game_projection_inbox;
DROP TABLE IF EXISTS chat_event_outbox;
DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS chat_blocks;
DROP TABLE IF EXISTS chat_private_requests;
DROP TABLE IF EXISTS chat_friendships;
DROP TABLE IF EXISTS chat_preferences;
DROP TABLE IF EXISTS chat_world_sessions;
DROP TABLE IF EXISTS chat_world_instances;
DROP TABLE IF EXISTS chat_server_nodes;
DROP TABLE IF EXISTS chat_characters;
DROP TABLE IF EXISTS chat_accounts;

COMMIT;
