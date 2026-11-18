BEGIN;

DROP TRIGGER IF EXISTS game_world_sessions_projection_event ON world_sessions;
DROP TRIGGER IF EXISTS game_server_registry_projection_event ON server_registry;
DROP TRIGGER IF EXISTS game_world_instances_projection_event ON world_instances;
DROP TRIGGER IF EXISTS game_souls_current_character_event ON souls;
DROP TRIGGER IF EXISTS game_characters_projection_event ON characters;

DROP FUNCTION IF EXISTS trg_game_world_session_event();
DROP FUNCTION IF EXISTS trg_game_server_node_event();
DROP FUNCTION IF EXISTS trg_game_world_instance_event();
DROP FUNCTION IF EXISTS trg_game_account_character_event();
DROP FUNCTION IF EXISTS trg_game_character_projection_event();
DROP FUNCTION IF EXISTS emit_game_domain_event(VARCHAR, VARCHAR, JSONB);

DROP TABLE IF EXISTS game_event_outbox;
DROP SEQUENCE IF EXISTS game_event_outbox_sequence;

COMMIT;
